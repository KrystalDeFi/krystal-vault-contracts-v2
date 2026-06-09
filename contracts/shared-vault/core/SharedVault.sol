// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";

import "../interfaces/ISharedVault.sol";
import "../interfaces/ISharedCommon.sol";
import "../interfaces/ISharedConfigManager.sol";
import "../interfaces/ISharedStrategy.sol";
import "../libraries/SharedSwapDataSignature.sol";
import "../libraries/SharedVaultPreviewLib.sol";
import "../../public-vault/interfaces/IWETH9.sol";

contract SharedVault is
  ERC20PermitUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  ERC721Holder,
  ERC1155Holder,
  IERC1271,
  ISharedVault
{
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  /// @dev Fixed share count minted to the first depositor regardless of deposit amount.
  ///      This decouples share units from any specific token's decimals and prevents
  ///      the initial share price from being dictated by deposit size.
  uint256 internal constant INITIAL_SHARES = 10e18;

  ISharedConfigManager public configManager;
  address public override vaultOwner;
  address internal vaultFactory;
  address internal operator;
  address public override weth;

  uint16 public override tokenCount;
  address[4] internal tokens;
  mapping(address => bool) public override isVaultToken;

  mapping(address => bool) internal admins;

  /// @inheritdoc ISharedVault
  /// @dev Locked at initialization. There is intentionally no setter — the value the depositor saw at
  ///      vault creation must remain the value applied to every subsequent withdrawal so the owner cannot
  ///      retroactively raise their performance-fee cut on existing deposits.
  uint16 public override vaultOwnerFeeBasisPoint;

  /// @dev Array of tracked LP positions
  Position[] internal positions;
  /// @dev Quick lookup: keccak256(nfpm, tokenId) => index+1 (0 = not tracked)
  mapping(bytes32 => uint256) internal positionIndex;

  modifier onlyOwner() {
    _onlyOwner();
    _;
  }

  modifier onlyAuthorized() {
    _onlyAuthorized();
    _;
  }

  modifier onlyOperator() {
    _onlyOperator();
    _;
  }

  modifier whenVaultNotPaused() {
    _whenVaultNotPaused();
    _;
  }

  function _onlyOwner() internal view {
    require(_msgSender() == vaultOwner, Unauthorized());
  }

  function _onlyAuthorized() internal view {
    require(
      _msgSender() == vaultOwner || admins[_msgSender()] || configManager.isWhitelistedCaller(_msgSender()),
      Unauthorized()
    );
  }

  function _onlyOperator() internal view {
    require(_msgSender() == operator, Unauthorized());
  }

  function _whenVaultNotPaused() internal view {
    require(!paused() && !configManager.isVaultPaused(), VaultPaused());
  }

  /// @notice Initializes the shared vault
  /// @param _operator Initial vault operator. The operator role is fixed at initialization —
  ///                  there is no post-deploy setter. Pass address(0) for a vault with no operator.
  /// @param _vaultOwnerFeeBasisPoint Vault-owner performance fee basis points (≤ 10_000). Locked at
  ///                  init — there is no setter so the fee depositors saw at vault creation cannot be
  ///                  retroactively raised on existing positions.
  function initialize(
    string calldata _name,
    address[4] calldata _tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    address _operator,
    address _configManager,
    address _weth,
    uint16 _vaultOwnerFeeBasisPoint
  ) public initializer {
    require(_configManager != address(0), ZeroAddress());
    require(_owner != address(0), ZeroAddress());
    require(_vaultOwnerFeeBasisPoint <= 10_000, ISharedCommon.InvalidVaultOwnerFeeBasisPoint());

    // Intentional: name is reused as symbol so vault share tokens display the
    // user-chosen vault name in wallets and block explorers as the ticker.
    __ERC20_init(_name, _name);
    __ERC20Permit_init(_name);
    __Pausable_init();
    __ReentrancyGuard_init();

    configManager = ISharedConfigManager(_configManager);
    vaultOwner = _owner;
    vaultFactory = _msgSender();
    weth = _weth;
    if (_operator != address(0)) operator = _operator;
    vaultOwnerFeeBasisPoint = _vaultOwnerFeeBasisPoint;
    emit VaultOwnerFeeBasisPointSet(_msgSender(), _vaultOwnerFeeBasisPoint);

    // Set up tokens
    uint8 count;
    for (uint256 i; i < 4;) {
      if (_tokens[i] != address(0)) {
        for (uint256 j; j < i;) {
          if (_tokens[j] == _tokens[i]) revert DuplicateToken();
          unchecked {
            j++;
          }
        }
        // Eagerly validate that decimals() is queryable so _minTokenAmt cannot revert
        // on subsequent deposits if the token only implements plain IERC20 without the
        // metadata extension. Failing here at init is far preferable to bricking deposits.
        try IERC20Metadata(_tokens[i]).decimals() returns (uint8) { }
        catch {
          revert InvalidToken();
        }
        tokens[i] = _tokens[i];
        isVaultToken[_tokens[i]] = true;
        unchecked {
          count++;
        }
      }
      unchecked {
        i++;
      }
    }
    require(count >= 2, NoTokensConfigured());
    tokenCount = count;

    // Mint initial shares if tokens were deposited by factory.
    // Always mints INITIAL_SHARES regardless of deposit size so the initial
    // share price is predictable and independent of token decimals.
    // Guard against FOT / short-transfer: require that the vault actually received
    // tokens for every slot that declares a non-zero initialAmount.  A 100% FOT
    // token passes safeTransferFrom without reverting but delivers zero to the
    // vault; minting shares against a zero balance would brick all future deposits.
    uint256 refIndex = type(uint256).max;
    for (uint256 i; i < 4;) {
      if (initialAmounts[i] > 0) {
        require(tokens[i] != address(0), InvalidToken());
        require(IERC20(tokens[i]).balanceOf(address(this)) > 0, ISharedCommon.InvalidAmount());
        if (refIndex == type(uint256).max) refIndex = i;
      }
      unchecked {
        i++;
      }
    }

    if (refIndex != type(uint256).max) {
      _mint(_owner, INITIAL_SHARES);
      emit VaultDeposit(_msgSender(), _owner, initialAmounts, INITIAL_SHARES);
    }
  }

  // ==================== Deposit / Withdraw ====================

  /// @notice Deposit tokens proportionally and receive shares.
  /// @dev Share ratio is based on TOTAL shareholder-owned balances (idle + LP principal + net LP fees).
  ///      Send ETH via msg.value to auto-wrap to WETH; amounts[wethIndex] must equal msg.value.
  ///      Only the needed WETH is wrapped; excess native ETH is sent back to the caller **after**
  ///      minting shares so a malicious depositor cannot receive a refund callback between balance
  ///      snapshots and share finalization (AMM / LP valuation manipulation).
  function deposit(uint256[4] calldata amounts, uint16 slippageBps, uint256 minShares)
    external
    payable
    override
    nonReentrant
    whenVaultNotPaused
    returns (uint256 shares)
  {
    shares = _deposit(amounts, slippageBps, minShares, _msgSender());
  }

  /// @notice Deposit tokens proportionally and mint shares to `receiver`.
  function deposit(uint256[4] calldata amounts, uint16 slippageBps, uint256 minShares, address receiver)
    external
    payable
    override
    nonReentrant
    whenVaultNotPaused
    returns (uint256 shares)
  {
    shares = _deposit(amounts, slippageBps, minShares, receiver);
  }

  function _deposit(uint256[4] calldata amounts, uint16 slippageBps, uint256 minShares, address receiver)
    internal
    returns (uint256 shares)
  {
    require(receiver != address(0), ZeroAddress());
    require(slippageBps <= 10_000, ISharedCommon.InvalidAmount());
    // Snapshot pre-deposit state before any balance mutation so share pricing is unaffected by the wrap.
    uint256 currentTotalSupply = totalSupply();
    uint256[4] memory totalBalancesBefore = _getTotalBalances();
    // Snapshot idle balances BEFORE the wrap/pull so we can measure actual ERC20 deltas.
    // This is the linchpin of FOT / non-standard ERC20 support (C-5): the vault credits
    // the depositor for tokens it actually received, never for the requested transferFrom amount.
    uint256[4] memory idleBeforePull = _getIdleBalances();
    uint256 wi = _validateWethDeposit(amounts);

    uint256[4] memory transferAmounts;
    uint256[4] memory actualPulled;
    uint256 excessEthRefund;
    if (currentTotalSupply == 0) {
      (transferAmounts, shares) = _firstDepositTransfers(amounts);
      excessEthRefund = _wrapWethDeposit(wi, transferAmounts);
      _pullDepositTokensExcludingWethSlot(wi, transferAmounts);
      // Measure actual token receipt (FOT-safe) before minting to guard against 100% FOT or
      // rebasing tokens that transfer 0 net. If we minted INITIAL_SHARES when every balance
      // stayed at zero, totalSupply() > 0 with zero balances would brick all future deposits
      // (every call to _subsequentDepositTransfers hits InvalidAmount because sharesOut stays
      // at type(uint256).max with no token meeting totalBalances[i] > 0).
      actualPulled = _measureActualPulled(idleBeforePull);
      for (uint256 i; i < 4;) {
        if (transferAmounts[i] > 0) require(actualPulled[i] > 0, InvalidAmount());
        unchecked {
          i++;
        }
      }
    } else {
      (transferAmounts) = _subsequentDepositTransfers(amounts, currentTotalSupply, totalBalancesBefore);
      excessEthRefund = _wrapWethDeposit(wi, transferAmounts);
      _pullDepositTokensExcludingWethSlot(wi, transferAmounts);
      // Measure actual tokens received (FOT-safe). Two downstream consumers of this snapshot:
      //
      //   (a) `_depositProportionalToAllPositions` uses `actualPulled` because the per-position
      //       LP top-up cannot push more tokens into a pool than the vault physically received
      //       from the depositor (NOT a user-facing constraint — depositors can always add new
      //       value; this is about the internal "push idle → LP" step that runs after the pull).
      //
      //   (b) `_computeSharesFromDelta` uses `transferAmounts` — the depositor's REQUIRED
      //       contribution set — as its filter. This prevents a 100% FOT / rebasing token from
      //       being silently skipped: if a required token has zero post-deposit delta, the
      //       function returns 0 and the outer `require(shares > 0)` reverts. Without this,
      //       the depositor would receive shares from the remaining tokens even though they
      //       didn't satisfy the vault ratio.
      actualPulled = _measureActualPulled(idleBeforePull);
      // Push proportional slices into LP positions. Slippage may cause `increaseLiquidity` to
      // consume less than the supplied amount; we re-snapshot balances after to measure what
      // was actually deposited (idle + LP) and compute shares from the resulting delta.
      _depositProportionalToAllPositions(currentTotalSupply, totalBalancesBefore, actualPulled, slippageBps);
      uint256[4] memory totalBalancesAfter = _getTotalBalances();
      shares = _computeSharesFromDelta(currentTotalSupply, totalBalancesBefore, totalBalancesAfter, transferAmounts);
      require(shares > 0, InsufficientShares());
    }

    // Share-price slippage guard. `slippageBps` above only bounds each position's LP-add ratio; it does
    // NOT bound shares-per-value, which is derived from the vault's spot-priced total balances and is
    // therefore manipulable within a block (deposit sandwich). Applied to both the first-deposit
    // (fixed INITIAL_SHARES) and subsequent (delta-derived) paths.
    require(shares >= minShares, InsufficientShares());

    _mint(receiver, shares);

    if (excessEthRefund > 0) {
      (bool ok,) = _msgSender().call{ value: excessEthRefund }("");
      require(ok, TransferFailed());
    }

    emit VaultDeposit(vaultFactory, receiver, actualPulled, shares);
  }

  /// @dev Measure how much each vault token actually arrived in the vault since `idleBefore`.
  ///      Used to credit depositors with the ACTUAL amount the vault holds, not the requested
  ///      transferFrom amount. Critical for fee-on-transfer (FOT) tokens and other non-standard
  ///      ERC20s where `transferFrom(X)` results in `< X` arriving at the recipient.
  ///      For the WETH slot (when ETH was sent via msg.value), the wrap is exact: actualPulled[wi]
  ///      equals the wrapped amount because IWETH9.deposit() always mints 1:1.
  function _measureActualPulled(uint256[4] memory idleBefore) internal view returns (uint256[4] memory actualPulled) {
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0)) {
        uint256 idleNow = IERC20(tokens[i]).balanceOf(address(this));
        if (idleNow > idleBefore[i]) actualPulled[i] = idleNow - idleBefore[i];
      }
      unchecked {
        i++;
      }
    }
  }

  /// @dev If caller sent ETH, returns validated WETH slot index; otherwise `type(uint256).max`.
  function _validateWethDeposit(uint256[4] calldata amounts) internal view returns (uint256 wi) {
    wi = type(uint256).max;
    if (msg.value > 0) {
      wi = _wethIndex();
      require(wi < 4, TokenNotConfigured());
      require(amounts[wi] == msg.value, InvalidAmount());
    }
  }

  /// @dev First deposit — always mints `INITIAL_SHARES`; full `amounts` are transferred.
  function _firstDepositTransfers(uint256[4] calldata amounts)
    internal
    view
    returns (uint256[4] memory transferAmounts, uint256 sharesOut)
  {
    uint256 refIndex = type(uint256).max;
    for (uint256 i; i < 4;) {
      if (amounts[i] > 0) {
        require(tokens[i] != address(0), InvalidToken());
        if (refIndex == type(uint256).max) refIndex = i;
        transferAmounts[i] = amounts[i];
      }
      unchecked {
        i++;
      }
    }
    require(refIndex != type(uint256).max, InvalidAmount());
    sharesOut = INITIAL_SHARES;
  }

  /// @dev Subsequent deposit — compute how many tokens to pull based on minimum ratio across tokens.
  ///      Shares are NOT computed here; they are derived from the post-LP-deposit balance delta so
  ///      that slippage-induced partial LP consumption is reflected in the final share count.
  ///
  ///      **Dust-proof rounding**: proportional slices are rounded UP (ceiling) and then floored to
  ///      `10 ** max(0, token.decimals() - configManager.minTokenPrecision())`. Without this:
  ///        (a) when a vault holds dust (e.g., 50 wei USDT + 100e18 tokenA), a depositor providing
  ///            `amounts = [1 USDT-worth of tokenA, 0]` would compute `transferAmounts[dust] = 0`
  ///            (floor of 0.5 wei) and receive shares for free, diluting existing holders; and
  ///        (b) when a token slot resolves to 1–few wei, SharedVaultGateway's swap aggregator
  ///            cannot produce that exact micro-amount to satisfy the deposit.
  ///      Rounding up + min-enforcement forces depositor overpayment on sub-threshold slices, so
  ///      existing holders are never diluted and the gateway always sees a swappable amount.
  function _subsequentDepositTransfers(
    uint256[4] calldata amounts,
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances
  ) internal view returns (uint256[4] memory transferAmounts) {
    transferAmounts = SharedVaultPreviewLib.subsequentDepositTransfers(
      amounts, currentTotalSupply, totalBalances, tokens, configManager
    );
  }

  /// @dev Compute shares earned by a depositor from the delta between pre- and post-LP-deposit balances.
  ///      Uses the minimum ratio across deposited tokens (binding constraint). Every token the depositor
  ///      paid (`requiredAmounts[i] > 0`) must show a strictly positive total-balance delta; if any
  ///      such token does not (LP valuation dropped due to price movement/sandwich), returns 0 so the
  ///      caller's `require(shares > 0)` reverts — preventing over-crediting from skipped tokens.
  function _computeSharesFromDelta(
    uint256 currentTotalSupply,
    uint256[4] memory balancesBefore,
    uint256[4] memory balancesAfter,
    uint256[4] memory requiredAmounts
  ) internal view returns (uint256 shares) {
    shares = type(uint256).max;
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0) && requiredAmounts[i] > 0) {
        // Deposited token must have a positive total-balance delta. If LP valuation moved against this
        // token (price impact / sandwich), clamp to 0 shares so the outer require reverts.
        if (balancesBefore[i] == 0 || balancesAfter[i] <= balancesBefore[i]) return 0;
        uint256 added = balancesAfter[i] - balancesBefore[i];
        uint256 s = FullMath.mulDiv(added, currentTotalSupply, balancesBefore[i]);
        if (s < shares) shares = s;
      }
      unchecked {
        i++;
      }
    }
    // If no token was deposited (should not happen; caller ensures at least one), return 0.
    if (shares == type(uint256).max) return 0;
  }

  /// @dev Wrap only `transferAmounts[wi]` from `msg.value` into WETH; return excess native ETH (not sent here).
  function _wrapWethDeposit(uint256 wi, uint256[4] memory transferAmounts) internal returns (uint256 excessEth) {
    if (msg.value == 0) return 0;

    uint256 wethNeeded = transferAmounts[wi];
    if (wethNeeded > 0) IWETH9(weth).deposit{ value: wethNeeded }();
    excessEth = msg.value - wethNeeded;
  }

  function _pullDepositTokensExcludingWethSlot(uint256 wi, uint256[4] memory transferAmounts) internal {
    for (uint256 i; i < 4;) {
      if (wi < 4 && i == wi) {
        unchecked {
          i++;
        }
        continue;
      }
      if (transferAmounts[i] > 0) {
        IERC20(tokens[i]).safeTransferFrom(_msgSender(), address(this), transferAmounts[i]);
      }
      unchecked {
        i++;
      }
    }
  }

  /// @dev Push proportional slices into tracked LP positions; no-op on first deposit or empty positions.
  ///
  ///      **Principal-only scaling**: the per-position top-up ratio is derived from each position's
  ///      *principal* (liquidity at the current price), NOT from `getPositionAmounts` which bundles
  ///      uncollected fees. `increaseLiquidity` can only consume tokens at the range ratio dictated
  ///      by the current tick, so mixing fee balances (whose ratio is set by historical swap flow, not
  ///      the range) into the desired amounts would either leak into idle silently (slippageBps == 0)
  ///      or revert via `amount*Min` (slippageBps > 0). Uncollected fees are therefore effectively
  ///      treated as idle: their shareholder-owned value still counts toward `_getTotalBalances` for
  ///      share pricing, net of platform/vault-owner performance fees, but they do not participate in
  ///      the LP top-up. The depositor's proportional share of those net fees remains in the vault as
  ///      a slightly higher idle reserve (or gets collected and proportionally returned on the next
  ///      `exitProportional`).
  ///
  ///      **Single binding share**: minimum-precision floors can intentionally make one token's pulled
  ///      amount larger than its proportional share. For in-range positions, clamp the LP top-up to the
  ///      smaller side's share so the floor excess stays idle instead of causing an off-ratio
  ///      `increaseLiquidity` slippage revert.
  function _depositProportionalToAllPositions(
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances,
    uint256[4] memory transferAmounts,
    uint16 slippageBps
  ) internal {
    if (currentTotalSupply == 0 || positions.length == 0) return;

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen;) {
      Position memory pos = positions[p];

      (uint256 posAmt0, uint256 posAmt1) =
        ISharedStrategy(pos.strategy).getPositionPrincipalAmounts(pos.nfpm, pos.tokenId);

      uint256 toAdd0;
      uint256 toAdd1;
      for (uint256 i; i < 4;) {
        if (tokens[i] == pos.token0 && totalBalances[i] > 0) {
          toAdd0 = FullMath.mulDiv(transferAmounts[i], posAmt0, totalBalances[i]);
        } else if (tokens[i] == pos.token1 && totalBalances[i] > 0) {
          toAdd1 = FullMath.mulDiv(transferAmounts[i], posAmt1, totalBalances[i]);
        }
        unchecked {
          i++;
        }
      }

      if (posAmt0 > 0 && posAmt1 > 0) {
        uint256 toAdd1AtToken0Share = FullMath.mulDiv(toAdd0, posAmt1, posAmt0);
        if (toAdd1AtToken0Share < toAdd1) {
          toAdd1 = toAdd1AtToken0Share;
        } else {
          uint256 toAdd0AtToken1Share = FullMath.mulDiv(toAdd1, posAmt0, posAmt1);
          if (toAdd0AtToken1Share < toAdd0) toAdd0 = toAdd0AtToken1Share;
        }
        if (toAdd0 == 0 || toAdd1 == 0) {
          toAdd0 = 0;
          toAdd1 = 0;
        }
      }

      if (toAdd0 > 0 || toAdd1 > 0) {
        (bool ok, bytes memory errData) = pos.strategy
          .delegatecall(
            abi.encodeCall(ISharedStrategy.depositProportional, (pos.nfpm, pos.tokenId, toAdd0, toAdd1, slippageBps))
          );
        if (!ok) {
          if (errData.length == 0) revert StrategyCallFailed();
          assembly {
            revert(add(32, errData), mload(errData))
          }
        }
      }

      unchecked {
        p++;
      }
    }
  }

  /// @notice Burn shares and withdraw proportional tokens.
  /// @dev For each tracked LP position the vault delegatecalls the strategy to exit
  ///      a proportional share of liquidity. Tokens returned to the vault are then
  ///      included in the idle balance withdrawn to the caller.
  ///
  ///      **Slippage protection model**: individual LP exits are called with
  ///      minAmount0=0, minAmount1=0 by design. Per-position slippage guards are
  ///      intentionally omitted so that a single position's tight bound cannot DoS
  ///      the entire withdrawal. Instead, `minAmounts` provides aggregate per-token
  ///      protection: if a sandwich attack reduces any LP exit return, the total
  ///      `amounts[i]` decreases and the outer check reverts the whole tx. Callers
  ///      should derive `minAmounts` from `previewWithdraw()` minus acceptable slippage.
  /// @param unwrap If true, any WETH output is unwrapped to native ETH before sending.
  function withdraw(uint256 shares, uint256[4] calldata minAmounts, bool unwrap)
    external
    override
    nonReentrant
    returns (uint256[4] memory amounts)
  {
    amounts = _withdraw(shares, minAmounts, unwrap, _msgSender());
  }

  /// @notice Burn `account` shares and withdraw proportional tokens to the caller.
  /// @dev `account` only selects whose shares are burned. When called via allowance, output tokens
  ///      and any unwrapped native ETH are sent to `_msgSender()`, not to `account`.
  function withdraw(uint256 shares, uint256[4] calldata minAmounts, bool unwrap, address account)
    external
    override
    nonReentrant
    returns (uint256[4] memory amounts)
  {
    amounts = _withdraw(shares, minAmounts, unwrap, account);
  }

  function _withdraw(uint256 shares, uint256[4] calldata minAmounts, bool unwrap, address account)
    internal
    returns (uint256[4] memory amounts)
  {
    require(account != address(0), ZeroAddress());
    require(shares > 0 && shares <= balanceOf(account), InsufficientShares());
    if (account != _msgSender()) _spendAllowance(account, _msgSender(), shares);

    uint256 currentTotalSupply = totalSupply();
    _burn(account, shares);

    // Pre-collect accumulated LP fees into idle BEFORE snapshotting idleBefore so they are
    // distributed proportionally by share ratio (not entirely to the current withdrawer).
    // A failure here must revert the whole withdrawal: a silent failure followed by exitProportional
    // would let the current withdrawer sweep all accumulated fees via collect(type(uint128).max).
    // NOTE: the V4/Pancake strategies internally tolerate a failing fee-sync collect when the position has
    // NO uncollected fees (a fragile/hostile pool hook reverting on the zero-liquidity collect), so such a
    // zero-fee position cannot brick withdraw here — see SharedV4StrategyLib._collectFees. When fees ARE
    // present the strategy re-reverts, so this require still fires and the guarantee above is preserved.
    uint256 posLenForCollect = positions.length;
    for (uint256 pc; pc < posLenForCollect;) {
      Position memory posForCollect = positions[pc];
      (bool collectOk,) = posForCollect.strategy
        .delegatecall(
          abi.encodeCall(
            ISharedStrategy.collectFees, (posForCollect.nfpm, posForCollect.tokenId, vaultOwnerFeeBasisPoint)
          )
        );
      require(collectOk, StrategyCallFailed());
      unchecked {
        pc++;
      }
    }

    // Snapshot idle balances BEFORE LP exits so the share ratio is applied only once
    // to the original idle tokens. LP exit returns are added in full (they already
    // represent the withdrawer's proportional share of each position).
    uint256[4] memory idleBefore = _getIdleBalances();

    // Exit proportional LP position liquidity.
    // Per-position min amounts are 0 — see function NatSpec for slippage model rationale.
    // We iterate the positions array; when a position is fully exited it is removed
    // (swap-with-last pattern), so we reload the length instead of incrementing p.
    uint256 p;
    while (p < positions.length) {
      Position memory pos = positions[p];

      (bool ok, bytes memory result) = pos.strategy
        .delegatecall(
          abi.encodeCall(
            ISharedStrategy.exitProportional,
            (pos.nfpm, pos.tokenId, shares, currentTotalSupply, 0, 0, vaultOwnerFeeBasisPoint)
          )
        );

      if (!ok) {
        if (result.length == 0) revert StrategyCallFailed();
        assembly {
          revert(add(32, result), mload(result))
        }
      }

      ISharedStrategy.PositionChange[] memory changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
      bool removed;
      for (uint256 c; c < changes.length;) {
        if (!changes[c].isAdd) {
          _removePosition(changes[c].nfpm, changes[c].tokenId);
          removed = true;
        }
        unchecked {
          c++;
        }
      }
      // Only advance p if the position was NOT removed; otherwise the swap-with-last
      // placed a new position at index p that we must process next iteration.
      if (!removed) {
        unchecked {
          p++;
        }
      }
    }

    // Compute withdrawal amounts:
    //   proportional share of original idle  +  full LP exit return
    // This avoids double-dilution where the LP return was previously re-multiplied
    // by shares/totalSupply.
    //
    // Dust is forwarded to the caller as-is. If this call originates from SharedVaultGateway,
    // the gateway will attempt to swap each token; if an amount is too small for the aggregator
    // it falls back to returning the token directly to the user. Zeroing dust here would silently
    // transfer value from the withdrawer to remaining vault holders.
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0)) {
        uint256 idleAfter = IERC20(tokens[i]).balanceOf(address(this));
        uint256 lpExitReturn = idleAfter - idleBefore[i];
        uint256 computed = FullMath.mulDiv(shares, idleBefore[i], currentTotalSupply) + lpExitReturn;
        amounts[i] = computed;
        require(amounts[i] >= minAmounts[i], InsufficientOutput());
        if (amounts[i] > 0) {
          if (unwrap && tokens[i] == weth) {
            IWETH9(weth).withdraw(amounts[i]);
            (bool sent,) = _msgSender().call{ value: amounts[i] }("");
            require(sent, SwapFailed(i));
          } else {
            IERC20(tokens[i]).safeTransfer(_msgSender(), amounts[i]);
          }
        }
      }
      unchecked {
        i++;
      }
    }

    emit VaultWithdraw(vaultFactory, account, amounts, shares);
  }

  // ==================== Execute (LP operations + swaps) ====================

  /// @notice Execute one or more actions atomically. See ISharedCommon.CallType for full semantics.
  ///
  ///   DELEGATECALL         — delegatecall target via ISharedStrategy.execute(data).
  ///                          Result is PositionChange[]: LP positions are tracked.
  ///                          New position entries (isAdd) require token0/token1 to be vault tokens.
  ///                          Token-only operations (harvest, swap-reward) return an empty array.
  ///   CALL                 — direct call to a swap aggregator (target must be a whitelisted swap router).
  ///                          action.data = abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata).
  ///                          Trust boundary for the opaque `swapCalldata` (W-4): it is NOT executed on
  ///                          trust — it must carry a whitelisted-signer signature
  ///                          (`SharedSwapDataSignature`) binding chainId/vault/router/tokenIn/tokenOut/
  ///                          amountIn/minAmountOut/keccak(swapData); tokenIn/tokenOut must be distinct
  ///                          vault tokens; the router allowance is scoped to exactly `amountIn` and reset
  ///                          to 0 after the call; and the realized tokenOut delta INTO the vault must be
  ///                          >= minAmountOut. The residual trust is only that the (governance-)whitelisted
  ///                          router and signer behave — a compromised signer signing minAmountOut == 0 is
  ///                          the boundary. Funds cannot be redirected to a non-vault recipient profitably.
  ///   CALL_WITH_POSITIONS  — direct call to a target that returns PositionChange[].
  ///                          action.data is forwarded as raw calldata; result is decoded as PositionChange[].
  ///                          The target is stored as pos.strategy and will be delegatecalled via
  ///                          exitProportional at withdrawal time — it must implement ISharedStrategy.
  ///                          No token pre-approval or balance check is performed on this path:
  ///                          the external contract manages its own token transfers (unlike CALL,
  ///                          where the vault is the initiator and owns the approval flow).
  function execute(Action[] calldata actions) external override nonReentrant onlyAuthorized whenVaultNotPaused {
    for (uint256 i; i < actions.length;) {
      Action calldata action = actions[i];

      if (action.callType == CallType.DELEGATECALL) {
        require(configManager.isWhitelistedTarget(action.target), InvalidTarget(action.target));
        // --- Strategy: delegatecall through ISharedStrategy.execute() interface ---
        // Strategies handle both LP operations (non-empty PositionChange[]) and token-only
        // operations like harvest/swap (empty PositionChange[]).
        (bool success, bytes memory result) =
          action.target.delegatecall(abi.encodeCall(ISharedStrategy.execute, (action.data)));

        if (!success) {
          if (result.length == 0) revert StrategyCallFailed();
          assembly {
            revert(add(32, result), mload(result))
          }
        }

        _applyPositionChanges(action.target, result, false);
      } else if (action.callType == CallType.CALL) {
        require(configManager.isWhitelistedSwapRouter(action.target), InvalidSwapRouter(action.target));
        // --- Swap: direct call to aggregator with token validation and slippage check ---
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes memory swapCalldata) =
          abi.decode(action.data, (address, address, uint256, uint256, bytes));

        require(isVaultToken[tokenIn], TokenNotConfigured());
        require(isVaultToken[tokenOut], TokenNotConfigured());
        require(tokenIn != tokenOut, InvalidOperation());

        swapCalldata = _verifySignedSwapData(action.target, tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        IERC20(tokenIn).safeResetAndApprove(action.target, amountIn);
        (bool success,) = action.target.call(swapCalldata);
        require(success, SwapFailed(i));
        IERC20(tokenIn).safeApprove(action.target, 0);

        uint256 amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        require(amountOut >= minAmountOut, InsufficientOutput());
      } else {
        require(configManager.isWhitelistedTarget(action.target), InvalidTarget(action.target));
        // --- CALL_WITH_POSITIONS: direct call whose return value is PositionChange[] ---
        (bool success, bytes memory result) = action.target.call(action.data);

        if (!success) {
          if (result.length == 0) revert StrategyCallFailed();
          assembly {
            revert(add(32, result), mload(result))
          }
        }

        _applyPositionChanges(action.target, result, true);
      }

      emit VaultExecute(vaultFactory, action.target, action.data);
      unchecked {
        i++;
      }
    }
  }

  function _verifySignedSwapData(
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory signedSwapData
  ) internal returns (bytes memory swapData) {
    return SharedSwapDataSignature.verify(
      configManager, address(this), swapRouter, tokenIn, tokenOut, amountIn, amountOutMin, signedSwapData
    );
  }

  /// @dev Decode a PositionChange[] from raw return bytes and update LP position tracking.
  ///      `probeStrategy` is enabled only for CALL_WITH_POSITIONS, where an arbitrary target
  ///      must prove it implements ISharedStrategy before the vault tracks a position for later
  ///      delegatecall-based exits.
  function _applyPositionChanges(address strategy, bytes memory result, bool probeStrategy) internal {
    if (result.length == 0) return;

    ISharedStrategy.PositionChange[] memory changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
    for (uint256 c; c < changes.length;) {
      if (changes[c].isAdd) {
        if (probeStrategy) {
          // Probe `getPositionAmounts` to confirm the target can value the position before it is tracked.
          (bool ok, bytes memory probeData) = strategy.staticcall(
            abi.encodeCall(ISharedStrategy.getPositionAmounts, (changes[c].nfpm, changes[c].tokenId))
          );
          require(ok && probeData.length >= 64, InvalidTarget(strategy));
        }
        // Verify canonical token pair via getPositionTokens: a buggy target can report any vault-token
        // pair but _getTotalBalances() would attribute LP value to the wrong assets, mispricing shares.
        (bool tokensOk, bytes memory tokensData) = strategy.staticcall(
          abi.encodeCall(ISharedStrategy.getPositionTokens, (changes[c].nfpm, changes[c].tokenId))
        );
        require(tokensOk && tokensData.length >= 64, InvalidTarget(strategy));
        (address canonToken0, address canonToken1) = abi.decode(tokensData, (address, address));
        require(canonToken0 == changes[c].token0 && canonToken1 == changes[c].token1, TokenNotConfigured());
        require(isVaultToken[changes[c].token0] && isVaultToken[changes[c].token1], TokenNotConfigured());
        // Verify vault owns the NFT before tracking it: an unowned position would misprice shares.
        (bool ownsNft, bytes memory ownerData) =
          changes[c].nfpm.staticcall(abi.encodeCall(IERC721.ownerOf, (changes[c].tokenId)));
        require(
          ownsNft && ownerData.length >= 32 && abi.decode(ownerData, (address)) == address(this), InvalidOperation()
        );
        _addPosition(strategy, changes[c].nfpm, changes[c].tokenId, changes[c].token0, changes[c].token1);
      } else {
        _verifyPositionExit(strategy, changes[c].nfpm, changes[c].tokenId);
        _removePosition(changes[c].nfpm, changes[c].tokenId);
      }
      unchecked {
        c++;
      }
    }
  }

  // ==================== View Functions ====================

  function getTokens() external view override returns (address[4] memory) {
    return tokens;
  }

  function getIdleBalances() external view override returns (uint256[4] memory) {
    return _getIdleBalances();
  }

  /// @inheritdoc ISharedVault
  function getTotalBalances() external view override returns (uint256[4] memory) {
    return _getTotalBalances();
  }

  function getPositionCount() external view override returns (uint256) {
    return positions.length;
  }

  function getPosition(uint256 index)
    external
    view
    returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1)
  {
    Position memory pos = positions[index];
    return (pos.strategy, pos.nfpm, pos.tokenId, pos.token0, pos.token1);
  }

  function previewDeposit(uint256[4] calldata amounts) external view override returns (uint256 shares) {
    shares = SharedVaultPreviewLib.previewDeposit(
      amounts, totalSupply(), _getTotalBalances(), tokens, configManager, INITIAL_SHARES
    );
  }

  /// @notice Preview token amounts returned for burning `_shares` NET of LP exit fees.
  /// @dev Returns the proportional share of (idle + LP principal + (1 − feeRate) × uncollected LP fees).
  ///      The fee deduction mirrors `SharedStrategyFeeConfig.performanceFeeConfig`: combined platform +
  ///      vault-owner basis points are clamped to 10000 (silent platform clamp) and applied only to the
  ///      uncollected-fees portion of each tracked position. Principal exits incur no perf/platform fee
  ///      (matching the V3 / Aerodrome flow in `SharedNfpmProportionalExit.decreaseLiquidityProportional`).
  ///      **Estimate, not exact (W-7)**: this is a close UPPER BOUND on what `withdraw` actually
  ///      transfers and can exceed it by a few wei per token per position. `previewWithdraw` divides once
  ///      over (idle + spot-valued LP), whereas `withdraw` floors the idle slice separately and then adds
  ///      the tokens actually returned by removing `floor(liquidity·shares/supply)` (a second layer of AMM
  ///      rounding). Always apply a slippage margin; do NOT pass `previewWithdraw()` verbatim as
  ///      `minAmounts`, or a 1-wei shortfall can trigger `InsufficientOutput`.
  function previewWithdraw(uint256 _shares) external view override returns (uint256[4] memory amounts) {
    amounts = SharedVaultPreviewLib.previewWithdraw(
      _shares, totalSupply(), _getIdleBalances(), positions, tokens, configManager, vaultOwnerFeeBasisPoint
    );
  }

  /// @inheritdoc ISharedVault
  function getMinDepositAmounts() external view override returns (uint256[4] memory minAmounts) {
    minAmounts = SharedVaultPreviewLib.minDepositAmounts(totalSupply(), _getTotalBalances(), tokens, configManager);
  }

  // ==================== Operator Sweep (non-vault tokens only) ====================

  function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to)
    external
    override
    onlyOperator
  {
    require(_tokens.length == amounts.length, InvalidAmount());
    for (uint256 i; i < _tokens.length;) {
      require(!isVaultToken[_tokens[i]], CannotSweepVaultToken());
      uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
      uint256 amount = amounts[i] > balance ? balance : amounts[i];
      IERC20(_tokens[i]).safeTransfer(to, amount);
      unchecked {
        i++;
      }
    }
  }

  function sweepNativeToken(uint256 amount, address to) external override onlyOperator {
    uint256 balance = address(this).balance;
    if (amount > balance) amount = balance;
    (bool success,) = to.call{ value: amount }("");
    require(success, SwapFailed(0));
  }

  function sweepERC721(address token, uint256 tokenId, address to) external override onlyOperator {
    bytes32 key = keccak256(abi.encodePacked(token, tokenId));
    require(positionIndex[key] == 0, CannotSweepVaultToken());
    IERC721(token).safeTransferFrom(address(this), to, tokenId);
  }

  function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external override onlyOperator {
    uint256 balance = IERC1155(token).balanceOf(address(this), tokenId);
    if (amount > balance) amount = balance;
    IERC1155(token).safeTransferFrom(address(this), to, tokenId, amount, "");
  }

  // ==================== Role Management ====================

  function grantAdminRole(address _address) external override onlyOwner {
    admins[_address] = true;
    emit SetVaultAdmin(vaultFactory, _address, true);
  }

  function revokeAdminRole(address _address) external override onlyOwner {
    admins[_address] = false;
    emit SetVaultAdmin(vaultFactory, _address, false);
  }

  function setPaused(bool _paused) external override onlyOwner {
    if (_paused) _pause();
    else _unpause();
    emit VaultPausedUpdated(vaultFactory, _paused);
  }

  function transferOwnership(address newOwner) external override onlyOwner {
    require(newOwner != address(0), ZeroAddress());
    emit VaultOwnerChanged(vaultFactory, vaultOwner, newOwner);
    vaultOwner = newOwner;
  }

  /// @inheritdoc ISharedVault
  /// @dev See `ISharedVault.dropPosition` regarding asymmetric custody when `operator` is set.
  ///      Callable by `vaultOwner` OR `operator`. The operator path exists as an emergency
  ///      escape hatch: if a strategy or NFPM becomes bricked, deposits/withdrawals revert
  ///      until the broken position is dropped. Allowing the operator to force-drop ensures
  ///      depositors are not stranded when the vault owner is unavailable.
  function dropPosition(address nfpm, uint256 tokenId) external override {
    require(_msgSender() == vaultOwner || (operator != address(0) && _msgSender() == operator), Unauthorized());
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    require(positionIndex[key] != 0, InvalidOperation());
    _removePosition(nfpm, tokenId);
    if (operator != address(0)) IERC721(nfpm).safeTransferFrom(address(this), operator, tokenId);
    emit PositionDropped(vaultFactory, nfpm, tokenId);
  }

  /// @inheritdoc ISharedVault
  /// @dev See `ISharedVault.recoverPosition` re `token0` / `token1` and vault token validation.
  function recoverPosition(address nfpm, uint256 tokenId, address strategy, address token0, address token1)
    external
    override
    onlyOperator
  {
    require(configManager.isWhitelistedNfpm(nfpm), InvalidNfpm(nfpm));
    require(isVaultToken[token0] && isVaultToken[token1], TokenNotConfigured());
    require(configManager.isWhitelistedTarget(strategy), InvalidTarget(strategy));
    (address actualToken0, address actualToken1) = ISharedStrategy(strategy).getPositionTokens(nfpm, tokenId);
    require(actualToken0 == token0 && actualToken1 == token1, TokenNotConfigured());
    IERC721(nfpm).transferFrom(operator, address(this), tokenId);
    require(IERC721(nfpm).ownerOf(tokenId) == address(this), InvalidOperation());
    _addPosition(strategy, nfpm, tokenId, token0, token1);
    emit PositionRecovered(vaultFactory, nfpm, tokenId);
  }

  // ==================== EIP-1271 ====================

  function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
    return
      SignatureChecker.isValidSignatureNow(vaultOwner, hash, signature) ? IERC1271.isValidSignature.selector : bytes4(0);
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function decimals() public pure override returns (uint8) {
    return 18;
  }

  // ==================== Internal: Position Tracking ====================

  function _addPosition(address strategy, address nfpm, uint256 tokenId, address token0, address token1) internal {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    if (positionIndex[key] != 0) return; // already tracked

    require(configManager.isWhitelistedNfpm(nfpm), InvalidNfpm(nfpm));
    require(positions.length < configManager.maxPositions(), TooManyPositions());
    // The no-liquidity-hook invariant is enforced by the strategy's `getPositionTokens`, which every
    // tracking entry (`_applyPositionChanges` and `recoverPosition`) calls before reaching here — so a
    // hooked pool is rejected at the staticcall above rather than being admitted into tracking.
    positions.push(Position(strategy, nfpm, tokenId, token0, token1));
    positionIndex[key] = positions.length; // index+1
  }

  function _removePosition(address nfpm, uint256 tokenId) internal {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    uint256 idx = positionIndex[key];
    if (idx == 0) return; // not tracked

    uint256 lastIdx = positions.length - 1;
    if (idx - 1 != lastIdx) {
      // swap with last
      Position memory lastPos = positions[lastIdx];
      positions[idx - 1] = lastPos;
      positionIndex[keccak256(abi.encodePacked(lastPos.nfpm, lastPos.tokenId))] = idx;
    }
    positions.pop();
    delete positionIndex[key];
  }

  /// @dev Before untracking a position, verify it is truly exited. If the vault still holds the NFT,
  ///      require the strategy reports zero amounts — a non-zero value means a live LP position would
  ///      be untracked, understating TVL and enabling mispriced deposits/withdrawals.
  function _verifyPositionExit(address strategy, address nfpm, uint256 tokenId) internal view {
    (bool callOk, bytes memory ownerData) = nfpm.staticcall(abi.encodeCall(IERC721.ownerOf, (tokenId)));
    if (callOk && ownerData.length >= 32 && abi.decode(ownerData, (address)) == address(this)) {
      (bool amtsOk, bytes memory amtsData) =
        strategy.staticcall(abi.encodeCall(ISharedStrategy.getPositionAmounts, (nfpm, tokenId)));
      require(amtsOk && amtsData.length >= 64, InvalidOperation());
      (uint256 a0, uint256 a1) = abi.decode(amtsData, (uint256, uint256));
      require(a0 == 0 && a1 == 0, InvalidOperation());
    }
  }

  // ==================== Internal: Balance Calculations ====================

  /// @dev Returns the index of the WETH token in the tokens array, or type(uint256).max if not found.
  function _wethIndex() internal view returns (uint256) {
    for (uint256 i; i < 4;) {
      if (tokens[i] == weth) return i;
      unchecked {
        i++;
      }
    }
    return type(uint256).max;
  }

  function _getIdleBalances() internal view returns (uint256[4] memory balances) {
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0)) balances[i] = IERC20(tokens[i]).balanceOf(address(this));
      unchecked {
        i++;
      }
    }
  }

  /// @notice Total shareholder-owned balances including idle tokens, LP principal, and net LP fees
  /// @dev Net of platform and vault-owner performance fees on the uncollected-fee portion (live read of
  ///      `configManager.platformFeeBasisPoint()`, so it reprices instantly when the platform fee changes).
  ///      See `ISharedVault.getTotalBalances` for the full integrator-facing semantics.
  function _getTotalBalances() internal view returns (uint256[4] memory balances) {
    return SharedVaultPreviewLib.computeTotalBalances(
      _getIdleBalances(), positions, tokens, configManager, vaultOwnerFeeBasisPoint
    );
  }

  receive() external payable { }
}
