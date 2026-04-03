// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";

import "../interfaces/ISharedVault.sol";
import "../interfaces/ISharedConfigManager.sol";
import "../interfaces/ISharedStrategy.sol";
import "../../public-vault/interfaces/IWETH9.sol";

contract SharedVault is ERC20PermitUpgradeable, ReentrancyGuard, ERC721Holder, ERC1155Holder, IERC1271, ISharedVault {
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  // Magic value per EIP-1271
  bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

  uint256 public constant SHARES_PRECISION = 1e18;

  /// @dev Fixed share count minted to the first depositor regardless of deposit amount.
  ///      This decouples share units from any specific token's decimals and prevents
  ///      the initial share price from being dictated by deposit size.
  uint256 public constant INITIAL_SHARES = 1e18;

  ISharedConfigManager public configManager;
  address public override vaultOwner;
  address public vaultFactory;
  address public operator;
  address public override weth;

  uint16 public override tokenCount;
  address[4] public tokens;
  mapping(address => bool) public override isVaultToken;

  mapping(address => bool) public admins;
  bool public paused;

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

  modifier whenNotPaused() {
    require(!paused && !configManager.isVaultPaused(), VaultPaused());
    _;
  }

  /// @notice Initializes the shared vault
  /// @param _operator Initial vault operator; address(0) means no operator until set by owner.
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
  ///      Only the needed WETH is wrapped — excess ETH is refunded as native ETH directly,
  ///      avoiding an unnecessary wrap→unwrap round-trip.
  function deposit(
    uint256[4] calldata amounts,
    uint256 minShares
  ) external payable override nonReentrant whenNotPaused returns (uint256 shares) {
    // Snapshot pre-deposit state before any balance mutation so share pricing is unaffected by the wrap.
    uint256 currentTotalSupply = totalSupply();
    uint256[4] memory totalBalances = _getTotalBalances();

    // Validate ETH: track the weth slot but defer the actual wrap until after share calculation.
    uint256 wi = type(uint256).max;
    if (msg.value > 0) {
      wi = _wethIndex();
      require(wi < 4, TokenNotConfigured());
      require(amounts[wi] == msg.value, InvalidAmount());
    }
    uint256[4] memory transferAmounts;

    if (currentTotalSupply == 0) {
      // First deposit — always mint the fixed INITIAL_SHARES constant.
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
      shares = INITIAL_SHARES;
    } else {
      // Subsequent deposit — compute shares as minimum ratio across all tokens to prevent
      // reference-token manipulation.
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
      require(shares != type(uint256).max, InvalidAmount());

      // Transfer only the proportional amount per token; excess stays with depositor.
      for (uint256 i; i < 4; ) {
        if (tokens[i] != address(0)) {
          if (totalBalances[i] == 0) {
            require(amounts[i] == 0, InvalidRatio());
          } else {
            transferAmounts[i] = FullMath.mulDiv(shares, totalBalances[i], currentTotalSupply);
            require(amounts[i] >= transferAmounts[i], InvalidRatio());
          }
        }
        unchecked {
          i++;
        }
      }
    }

    require(shares >= minShares, InsufficientShares());

    // ETH handling: wrap only the needed amount; refund excess as raw ETH.
    // This avoids the old wrap-all → unwrap-excess pattern (two WETH operations).
    // If transferAmounts[wi] rounds to zero (dust deposit), the full msg.value is
    // refunded without touching WETH at all.
    if (msg.value > 0) {
      uint256 wethNeeded = transferAmounts[wi]; // 0 in dust edge-case
      if (wethNeeded > 0) {
        IWETH9(weth).deposit{ value: wethNeeded }();
      }
      uint256 excess = msg.value - wethNeeded;
      if (excess > 0) {
        (bool ok, ) = _msgSender().call{ value: excess }("");
        require(ok, SwapFailed());
      }
    }

    for (uint256 i; i < 4; ) {
      // Skip WETH slot — already handled above via ETH wrap.
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

    _mint(_msgSender(), shares);

    emit VaultDeposit(vaultFactory, _msgSender(), transferAmounts, shares);
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
    uint256[4] memory idleBefore;
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) {
        idleBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
      }
      unchecked {
        i++;
      }
    }

    // Exit proportional LP position liquidity.
    // Per-position min amounts are 0 — see function NatSpec for slippage model rationale.
    // We iterate the positions array; when a position is fully exited it is removed
    // (swap-with-last pattern), so we reload the length instead of incrementing p.
    uint256 p;
    while (p < positions.length) {
      Position memory pos = positions[p];

      (bool ok, bytes memory result) = pos.strategy.delegatecall(
        abi.encodeCall(ISharedStrategy.exitProportional, (pos.nfpm, pos.tokenId, shares, currentTotalSupply, 0, 0))
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

  /// @notice Execute one or more actions atomically.
  ///
  ///   callType = DELEGATECALL → delegatecall the target as a whitelisted strategy.
  ///                             Returned PositionChange[] updates LP position tracking.
  ///   callType = CALL         → direct call the target as a swap aggregator.
  ///                             action.data must be abi.encode(tokenIn, tokenOut, amountIn,
  ///                             minAmountOut, swapCalldata). tokenIn/tokenOut must be vault
  ///                             tokens; output balance delta is checked against minAmountOut.
  function execute(Action[] calldata actions) external override nonReentrant onlyAuthorized whenNotPaused {
    for (uint256 i; i < actions.length; ) {
      Action calldata action = actions[i];
      require(configManager.isWhitelistedTarget(action.target), InvalidTarget(action.target));

      if (action.callType == CallType.DELEGATECALL) {
        // --- Strategy: delegatecall + LP position tracking ---
        (bool success, bytes memory result) = action.target.delegatecall(
          abi.encodeCall(ISharedStrategy.execute, (action.data))
        );

        if (!success) {
          if (result.length == 0) revert StrategyCallFailed();
          assembly {
            revert(add(32, result), mload(result))
          }
        }

        if (result.length > 0) {
          ISharedStrategy.PositionChange[] memory changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
          for (uint256 c; c < changes.length; ) {
            if (changes[c].isAdd) {
              _addPosition(action.target, changes[c].nfpm, changes[c].tokenId, changes[c].token0, changes[c].token1);
            } else {
              _removePosition(changes[c].nfpm, changes[c].tokenId);
            }
            unchecked {
              c++;
            }
          }
        }
      } else {
        // --- Swap: direct call to aggregator with token validation ---
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
      }

      emit VaultExecute(vaultFactory, action.target, action.data);
      unchecked {
        i++;
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

  function setOperator(address _operator) external override onlyOwner {
    require(_operator != address(0), ZeroAddress());
    emit SetVaultOperator(vaultFactory, operator, _operator);
    operator = _operator;
  }

  function setPaused(bool _paused) external override onlyOwner {
    paused = _paused;
    emit VaultPausedUpdated(vaultFactory, _paused);
  }

  function transferOwnership(address newOwner) external override onlyOwner {
    require(newOwner != address(0), ZeroAddress());
    emit VaultOwnerChanged(vaultFactory, vaultOwner, newOwner);
    vaultOwner = newOwner;
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
    if (positionIndex[key] != 0) return; // already tracked

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
