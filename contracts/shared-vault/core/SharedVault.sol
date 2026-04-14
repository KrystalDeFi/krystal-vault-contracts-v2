// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";

import "../interfaces/ISharedVault.sol";
import "../interfaces/ISharedCommon.sol";
import "../interfaces/ISharedConfigManager.sol";
import "../interfaces/ISharedStrategy.sol";
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

  // Magic value per EIP-1271
  bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

  uint256 public constant SHARES_PRECISION = 1e18;

  /// @dev Fixed share count minted to the first depositor regardless of deposit amount.
  ///      This decouples share units from any specific token's decimals and prevents
  ///      the initial share price from being dictated by deposit size.
  uint256 public constant INITIAL_SHARES = 10e18;

  ISharedConfigManager public configManager;
  address public override vaultOwner;
  address public vaultFactory;
  address public operator;
  address public override weth;

  uint16 public override tokenCount;
  address[4] public tokens;
  mapping(address => bool) public override isVaultToken;

  mapping(address => bool) public admins;

  /// @inheritdoc ISharedVault
  uint16 public override vaultOwnerFeeBasisPoint;

  /// @dev Array of tracked LP positions
  Position[] public positions;
  /// @dev Quick lookup: keccak256(nfpm, tokenId) => index+1 (0 = not tracked)
  mapping(bytes32 => uint256) internal positionIndex;

  modifier onlyOwner() {
    require(_msgSender() == vaultOwner, Unauthorized());
    _;
  }

  modifier onlyAuthorized() {
    require(
      _msgSender() == vaultOwner || admins[_msgSender()] || configManager.isWhitelistedCaller(_msgSender()),
      Unauthorized()
    );
    _;
  }

  modifier onlyOperator() {
    require(_msgSender() == operator, Unauthorized());
    _;
  }

  modifier whenVaultNotPaused() {
    require(!paused() && !configManager.isVaultPaused(), VaultPaused());
    _;
  }

  /// @notice Initializes the shared vault
  /// @param _operator Initial vault operator. The operator role is fixed at initialization —
  ///                  there is no post-deploy setter. Pass address(0) for a vault with no operator.
  function initialize(
    string calldata _name,
    address[4] calldata _tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    address _operator,
    address _configManager,
    address _weth
  ) public initializer {
    require(_configManager != address(0), ZeroAddress());
    require(_owner != address(0), ZeroAddress());

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

    // Set up tokens
    uint8 count;
    for (uint256 i; i < 4; ) {
      if (_tokens[i] != address(0)) {
        for (uint256 j; j < i; ) {
          if (_tokens[j] == _tokens[i]) revert DuplicateToken();
          unchecked {
            j++;
          }
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
    uint256 refIndex = type(uint256).max;
    for (uint256 i; i < 4; ) {
      if (initialAmounts[i] > 0) {
        require(tokens[i] != address(0), InvalidToken());
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
  /// @dev Share ratio is based on TOTAL balances (idle + LP positions valued by strategies).
  ///      Send ETH via msg.value to auto-wrap to WETH; amounts[wethIndex] must equal msg.value.
  ///      Only the needed WETH is wrapped; excess native ETH is sent back to the caller **after**
  ///      minting shares so a malicious depositor cannot receive a refund callback between balance
  ///      snapshots and share finalization (AMM / LP valuation manipulation).
  function deposit(
    uint256[4] calldata amounts,
    uint16 slippageBps
  ) external payable override nonReentrant whenVaultNotPaused returns (uint256 shares) {
    require(slippageBps <= 10000, ISharedCommon.InvalidAmount());
    // Snapshot pre-deposit state before any balance mutation so share pricing is unaffected by the wrap.
    uint256 currentTotalSupply = totalSupply();
    uint256[4] memory totalBalancesBefore = _getTotalBalances();
    uint256 wi = _validateWethDeposit(amounts);

    uint256[4] memory transferAmounts;
    uint256 excessEthRefund;
    if (currentTotalSupply == 0) {
      (transferAmounts, shares) = _firstDepositTransfers(amounts);
      excessEthRefund = _wrapWethDeposit(wi, transferAmounts);
      _pullDepositTokensExcludingWethSlot(wi, transferAmounts);
      // No LP positions exist on first deposit — INITIAL_SHARES is always the correct amount.
    } else {
      (transferAmounts) = _subsequentDepositTransfers(amounts, currentTotalSupply, totalBalancesBefore);
      excessEthRefund = _wrapWethDeposit(wi, transferAmounts);
      _pullDepositTokensExcludingWethSlot(wi, transferAmounts);
      // Push tokens into LP positions. Slippage may cause the LP to consume less than
      // the full transferAmounts, so we re-snapshot balances after to measure what was
      // actually deposited and compute shares from that delta.
      _depositProportionalToAllPositions(currentTotalSupply, totalBalancesBefore, transferAmounts, slippageBps);
      uint256[4] memory totalBalancesAfter = _getTotalBalances();
      shares = _computeSharesFromDelta(currentTotalSupply, totalBalancesBefore, totalBalancesAfter);
    }

    _mint(_msgSender(), shares);

    if (excessEthRefund > 0) {
      (bool ok, ) = _msgSender().call{ value: excessEthRefund }("");
      require(ok, TransferFailed());
    }

    emit VaultDeposit(vaultFactory, _msgSender(), transferAmounts, shares);
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
  function _firstDepositTransfers(
    uint256[4] calldata amounts
  ) internal view returns (uint256[4] memory transferAmounts, uint256 sharesOut) {
    uint256 refIndex = type(uint256).max;
    for (uint256 i; i < 4; ) {
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
  function _subsequentDepositTransfers(
    uint256[4] calldata amounts,
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances
  ) internal view returns (uint256[4] memory transferAmounts) {
    // Find the binding token: the one that would yield the fewest shares.
    uint256 sharesOut = type(uint256).max;
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
        uint256 s = FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i]);
        if (s < sharesOut) sharesOut = s;
      }
      unchecked {
        i++;
      }
    }
    require(sharesOut != type(uint256).max, InvalidAmount());

    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) {
        if (totalBalances[i] == 0) {
          require(amounts[i] == 0, InvalidRatio());
        } else {
          transferAmounts[i] = FullMath.mulDiv(sharesOut, totalBalances[i], currentTotalSupply);
          require(amounts[i] >= transferAmounts[i], InvalidRatio());
        }
      }
      unchecked {
        i++;
      }
    }
  }

  /// @dev Compute shares earned by a depositor from the delta between pre- and post-LP-deposit balances.
  ///      Uses the minimum ratio across all tokens (binding constraint) so that a token that saw less
  ///      LP consumption due to slippage is not over-credited. Reverts if no balance increased.
  ///      Tokens whose total balance did not strictly increase are skipped (avoids underflow if LP marks move down).
  function _computeSharesFromDelta(
    uint256 currentTotalSupply,
    uint256[4] memory balancesBefore,
    uint256[4] memory balancesAfter
  ) internal view returns (uint256 shares) {
    shares = type(uint256).max;
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0) && balancesBefore[i] > 0 && balancesAfter[i] > balancesBefore[i]) {
        uint256 added = balancesAfter[i] - balancesBefore[i];
        uint256 s = FullMath.mulDiv(added, currentTotalSupply, balancesBefore[i]);
        if (s < shares) shares = s;
      }
      unchecked {
        i++;
      }
    }
    require(shares != type(uint256).max, InsufficientShares());
  }

  /// @dev Wrap only `transferAmounts[wi]` from `msg.value` into WETH; return excess native ETH (not sent here).
  function _wrapWethDeposit(uint256 wi, uint256[4] memory transferAmounts) internal returns (uint256 excessEth) {
    if (msg.value == 0) return 0;

    uint256 wethNeeded = transferAmounts[wi];
    if (wethNeeded > 0) {
      IWETH9(weth).deposit{ value: wethNeeded }();
    }
    excessEth = msg.value - wethNeeded;
  }

  function _pullDepositTokensExcludingWethSlot(uint256 wi, uint256[4] memory transferAmounts) internal {
    for (uint256 i; i < 4; ) {
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
  function _depositProportionalToAllPositions(
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances,
    uint256[4] memory transferAmounts,
    uint16 slippageBps
  ) internal {
    if (currentTotalSupply == 0 || positions.length == 0) return;

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen; ) {
      Position memory pos = positions[p];

      (uint256 posAmt0, uint256 posAmt1) = ISharedStrategy(pos.strategy).getPositionAmounts(pos.nfpm, pos.tokenId);

      uint256 toAdd0;
      uint256 toAdd1;
      for (uint256 i; i < 4; ) {
        if (tokens[i] == pos.token0 && totalBalances[i] > 0) {
          toAdd0 = FullMath.mulDiv(transferAmounts[i], posAmt0, totalBalances[i]);
        } else if (tokens[i] == pos.token1 && totalBalances[i] > 0) {
          toAdd1 = FullMath.mulDiv(transferAmounts[i], posAmt1, totalBalances[i]);
        }
        unchecked {
          i++;
        }
      }

      if (toAdd0 > 0 || toAdd1 > 0) {
        (bool ok, bytes memory errData) = pos.strategy.delegatecall(
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
  function withdraw(
    uint256 shares,
    uint256[4] calldata minAmounts,
    bool unwrap
  ) external override nonReentrant returns (uint256[4] memory amounts) {
    require(shares > 0 && shares <= balanceOf(_msgSender()), InsufficientShares());

    uint256 currentTotalSupply = totalSupply();
    _burn(_msgSender(), shares);

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

      (bool ok, bytes memory result) = pos.strategy.delegatecall(
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
      for (uint256 c; c < changes.length; ) {
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
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) {
        uint256 idleAfter = IERC20(tokens[i]).balanceOf(address(this));
        uint256 lpExitReturn = idleAfter - idleBefore[i];
        amounts[i] = FullMath.mulDiv(shares, idleBefore[i], currentTotalSupply) + lpExitReturn;
        require(amounts[i] >= minAmounts[i], InsufficientOutput());
        if (amounts[i] > 0) {
          if (unwrap && tokens[i] == weth) {
            IWETH9(weth).withdraw(amounts[i]);
            (bool sent, ) = _msgSender().call{ value: amounts[i] }("");
            require(sent, SwapFailed());
          } else {
            IERC20(tokens[i]).safeTransfer(_msgSender(), amounts[i]);
          }
        }
      }
      unchecked {
        i++;
      }
    }

    emit VaultWithdraw(vaultFactory, _msgSender(), amounts, shares);
  }

  // ==================== Execute (LP operations + swaps) ====================

  /// @notice Execute one or more actions atomically. See ISharedCommon.CallType for full semantics.
  ///
  ///   DELEGATECALL         — delegatecall target via ISharedStrategy.execute(data).
  ///                          Result is PositionChange[]: LP positions are tracked.
  ///                          Token-only operations (harvest, swap-reward) return an empty array.
  ///   CALL                 — direct call to a swap aggregator.
  ///                          action.data = abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata).
  ///                          tokenIn/tokenOut must be vault tokens; output delta checked against minAmountOut.
  ///   CALL_WITH_POSITIONS  — direct call to a target that returns PositionChange[].
  ///                          action.data is forwarded as raw calldata; result is decoded as PositionChange[].
  ///                          The target is stored as pos.strategy and will be delegatecalled via
  ///                          exitProportional at withdrawal time — it must implement ISharedStrategy.
  ///                          No token pre-approval or balance check is performed on this path:
  ///                          the external contract manages its own token transfers (unlike CALL,
  ///                          where the vault is the initiator and owns the approval flow).
  function execute(
    Action[] calldata actions,
    PositionStrategyUpdate[] calldata strategyUpdates
  ) external override nonReentrant onlyAuthorized whenVaultNotPaused {
    for (uint256 u; u < strategyUpdates.length; ) {
      PositionStrategyUpdate calldata upd = strategyUpdates[u];
      require(configManager.isWhitelistedTarget(upd.strategy), InvalidTarget(upd.strategy));
      bytes32 key = keccak256(abi.encodePacked(upd.nfpm, upd.tokenId));
      uint256 idx = positionIndex[key];
      require(idx != 0, InvalidOperation());
      address oldStrategy = positions[idx - 1].strategy;
      if (oldStrategy != upd.strategy) {
        positions[idx - 1].strategy = upd.strategy;
        emit PositionStrategyMigrated(vaultFactory, upd.nfpm, upd.tokenId, oldStrategy, upd.strategy);
      }
      unchecked {
        u++;
      }
    }

    for (uint256 i; i < actions.length; ) {
      Action calldata action = actions[i];
      require(configManager.isWhitelistedTarget(action.target), InvalidTarget(action.target));

      if (action.callType == CallType.DELEGATECALL) {
        // --- Strategy: delegatecall through ISharedStrategy.execute() interface ---
        // Strategies handle both LP operations (non-empty PositionChange[]) and token-only
        // operations like harvest/swap (empty PositionChange[]).
        (bool success, bytes memory result) = action.target.delegatecall(
          abi.encodeCall(ISharedStrategy.execute, (action.data))
        );

        if (!success) {
          if (result.length == 0) revert StrategyCallFailed();
          assembly {
            revert(add(32, result), mload(result))
          }
        }

        _applyPositionChanges(action.target, result);
      } else if (action.callType == CallType.CALL) {
        // --- Swap: direct call to aggregator with token validation and slippage check ---
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes memory swapCalldata) = abi
          .decode(action.data, (address, address, uint256, uint256, bytes));

        require(isVaultToken[tokenIn], TokenNotConfigured());
        require(isVaultToken[tokenOut], TokenNotConfigured());

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        IERC20(tokenIn).safeResetAndApprove(action.target, amountIn);

        (bool success, ) = action.target.call(swapCalldata);
        require(success, SwapFailed());

        uint256 amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        require(amountOut >= minAmountOut, InsufficientOutput());
      } else {
        // --- CALL_WITH_POSITIONS: direct call whose return value is PositionChange[] ---
        (bool success, bytes memory result) = action.target.call(action.data);

        if (!success) {
          if (result.length == 0) revert StrategyCallFailed();
          assembly {
            revert(add(32, result), mload(result))
          }
        }

        _applyPositionChangesChecked(action.target, result);
      }

      emit VaultExecute(vaultFactory, action.target, action.data);
      unchecked {
        i++;
      }
    }
  }

  /// @dev Decode a PositionChange[] from raw return bytes and update LP position tracking.
  ///      Shared by DELEGATECALL execution path.
  function _applyPositionChanges(address strategy, bytes memory result) internal {
    if (result.length == 0) return;

    ISharedStrategy.PositionChange[] memory changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
    for (uint256 c; c < changes.length; ) {
      if (changes[c].isAdd) {
        _addPosition(strategy, changes[c].nfpm, changes[c].tokenId, changes[c].token0, changes[c].token1);
      } else {
        _removePosition(changes[c].nfpm, changes[c].tokenId);
      }
      unchecked {
        c++;
      }
    }
  }

  /// @dev Same as _applyPositionChanges but used for the CALL_WITH_POSITIONS path.
  ///      Before tracking a new position, verifies that `strategy` implements ISharedStrategy
  ///      by probing `getPositionAmounts`. Positions stored here are later exited via
  ///      delegatecall to `exitProportional`; a target that lacks that selector would brick
  ///      all future withdrawals for every vault depositor.
  function _applyPositionChangesChecked(address strategy, bytes memory result) internal {
    if (result.length == 0) return;

    ISharedStrategy.PositionChange[] memory changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
    for (uint256 c; c < changes.length; ) {
      if (changes[c].isAdd) {
        // Probe `getPositionAmounts` via staticcall to verify the strategy implements ISharedStrategy.
        // A staticcall to a view function reliably distinguishes "selector present" from "selector absent":
        //   ok == true → call succeeded and returned data
        //   ok == false && probeData.length > 0 → function exists but reverted with a reason
        //   ok == false && probeData.length == 0 → selector absent (or contract has no code)
        // Note: `exitProportional` is NOT probed here because it is a state-mutating function.
        // A staticcall to a non-view function that writes storage reverts with *empty* data — the same
        // signal as "selector missing" — making the probe unreliable. The configManager whitelist is the
        // primary trust boundary ensuring strategies implement the full ISharedStrategy interface.
        (bool ok, bytes memory probeData) = strategy.staticcall(
          abi.encodeCall(ISharedStrategy.getPositionAmounts, (changes[c].nfpm, changes[c].tokenId))
        );
        require(ok || probeData.length > 0, InvalidTarget(strategy));
        _addPosition(strategy, changes[c].nfpm, changes[c].tokenId, changes[c].token0, changes[c].token1);
      } else {
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

  function getTotalBalances() external view override returns (uint256[4] memory) {
    return _getTotalBalances();
  }

  function getPositionCount() external view override returns (uint256) {
    return positions.length;
  }

  function getPosition(
    uint256 index
  ) external view returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1) {
    Position memory pos = positions[index];
    return (pos.strategy, pos.nfpm, pos.tokenId, pos.token0, pos.token1);
  }

  function previewDeposit(uint256[4] calldata amounts) external view override returns (uint256 shares) {
    uint256 currentTotalSupply = totalSupply();
    uint256[4] memory totalBalances = _getTotalBalances();

    if (currentTotalSupply == 0) {
      for (uint256 i; i < 4; ) {
        if (amounts[i] > 0) {
          return INITIAL_SHARES;
        }
        unchecked {
          i++;
        }
      }
    } else {
      shares = type(uint256).max;
      for (uint256 i; i < 4; ) {
        if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
          uint256 s = FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i]);
          if (s < shares) shares = s;
        }
        unchecked {
          i++;
        }
      }
      if (shares == type(uint256).max) shares = 0;
    }
  }

  /// @notice Preview token amounts returned for burning `_shares`.
  /// @dev Computes proportional share of total balances (idle + LP position principal + uncollected fees).
  ///      **Does NOT deduct LP exit fees** (platform fee and vault-owner performance fee) that are
  ///      charged during the actual `withdraw()`. Actual received amounts will be slightly lower.
  ///      Callers should apply an additional slippage margin beyond LP exit fees when deriving `minAmounts`.
  function previewWithdraw(uint256 _shares) external view override returns (uint256[4] memory amounts) {
    uint256 currentTotalSupply = totalSupply();
    if (currentTotalSupply == 0) return amounts;

    uint256[4] memory totalBalances = _getTotalBalances();
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) {
        amounts[i] = FullMath.mulDiv(_shares, totalBalances[i], currentTotalSupply);
      }
      unchecked {
        i++;
      }
    }
  }

  // ==================== Operator Sweep (non-vault tokens only) ====================

  function sweepTokens(
    address[] calldata _tokens,
    uint256[] calldata amounts,
    address to
  ) external override onlyOperator {
    require(_tokens.length == amounts.length, InvalidAmount());
    for (uint256 i; i < _tokens.length; ) {
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
    (bool success, ) = to.call{ value: amount }("");
    require(success, SwapFailed());
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
    if (_paused) {
      _pause();
    } else {
      _unpause();
    }
    emit VaultPausedUpdated(vaultFactory, _paused);
  }

  /// @inheritdoc ISharedVault
  function setVaultOwnerFeeBasisPoint(uint16 basisPoints) external override onlyOwner {
    require(basisPoints <= 10_000, ISharedCommon.InvalidVaultOwnerFeeBasisPoint());
    vaultOwnerFeeBasisPoint = basisPoints;
    emit VaultOwnerFeeBasisPointUpdated(vaultFactory, basisPoints);
  }

  function transferOwnership(address newOwner) external override onlyOwner {
    require(newOwner != address(0), ZeroAddress());
    emit VaultOwnerChanged(vaultFactory, vaultOwner, newOwner);
    vaultOwner = newOwner;
  }

  /// @inheritdoc ISharedVault
  function dropPosition(address nfpm, uint256 tokenId) external override onlyOwner {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    require(positionIndex[key] != 0, InvalidOperation());
    _removePosition(nfpm, tokenId);
    emit PositionDropped(vaultFactory, nfpm, tokenId);
  }

  // ==================== EIP-1271 ====================

  function isValidSignature(bytes32 hash, bytes memory signature) public view override returns (bytes4 magicValue) {
    bool success = SignatureChecker.isValidSignatureNow(vaultOwner, hash, signature);
    magicValue = success ? MAGIC_VALUE : bytes4("");
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
    uint256 idx = positionIndex[key];
    if (idx != 0) {
      // Position already tracked — update strategy to reflect current executor.
      // Mirrors Vault.sol's _addAssets pattern: re-executing via a new strategy naturally migrates the pointer.
      address oldStrategy = positions[idx - 1].strategy;
      if (oldStrategy != strategy) {
        positions[idx - 1].strategy = strategy;
        emit PositionStrategyMigrated(vaultFactory, nfpm, tokenId, oldStrategy, strategy);
      }
      return;
    }

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

  // ==================== Internal: Balance Calculations ====================

  /// @dev Returns the index of the WETH token in the tokens array, or type(uint256).max if not found.
  function _wethIndex() internal view returns (uint256) {
    for (uint256 i; i < 4; ) {
      if (tokens[i] == weth) return i;
      unchecked {
        i++;
      }
    }
    return type(uint256).max;
  }

  function _getIdleBalances() internal view returns (uint256[4] memory balances) {
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) {
        balances[i] = IERC20(tokens[i]).balanceOf(address(this));
      }
      unchecked {
        i++;
      }
    }
  }

  /// @notice Total balances including idle tokens + LP position amounts valued by strategies
  function _getTotalBalances() internal view returns (uint256[4] memory balances) {
    balances = _getIdleBalances();

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen; ) {
      Position memory pos = positions[p];

      // Delegate valuation to the strategy that created the position
      (uint256 amount0, uint256 amount1) = ISharedStrategy(pos.strategy).getPositionAmounts(pos.nfpm, pos.tokenId);

      // Map amounts back to vault token indices
      for (uint256 i; i < 4; ) {
        if (tokens[i] == pos.token0) balances[i] += amount0;
        else if (tokens[i] == pos.token1) balances[i] += amount1;
        unchecked {
          i++;
        }
      }
      unchecked {
        p++;
      }
    }
  }

  receive() external payable {}
}
