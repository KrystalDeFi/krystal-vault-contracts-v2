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

contract SharedVault is ERC20PermitUpgradeable, ReentrancyGuard, ERC721Holder, ERC1155Holder, IERC1271, ISharedVault {
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  // Magic value per EIP-1271
  bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

  uint256 public constant SHARES_PRECISION = 1e18;

  /// @dev Tracked LP position
  struct Position {
    address strategy; // Strategy contract (used for getPositionAmounts valuation)
    address nfpm; // NFT Position Manager
    uint256 tokenId; // Position NFT ID
    address token0; // Pool token0
    address token1; // Pool token1
  }

  ISharedConfigManager public configManager;
  address public override vaultOwner;
  address public vaultFactory;
  address public operator;

  uint8 public override tokenCount;
  address[4] public tokens;
  mapping(address => bool) public override isVaultToken;

  mapping(address => bool) public admins;
  bool public paused;

  /// @dev Array of tracked LP positions
  Position[] public positions;
  /// @dev Quick lookup: keccak256(nfpm, tokenId) => index+1 (0 = not tracked)
  mapping(bytes32 => uint256) internal positionIndex;

  modifier onlyOwner() {
    require(msg.sender == vaultOwner, Unauthorized());
    _;
  }

  modifier onlyAuthorized() {
    require(
      msg.sender == vaultOwner || admins[msg.sender] || configManager.isWhitelistedCaller(msg.sender), Unauthorized()
    );
    _;
  }

  modifier onlyOperator() {
    require(msg.sender == operator, Unauthorized());
    _;
  }

  modifier whenNotPaused() {
    require(!paused && !configManager.isVaultPaused(), VaultPaused());
    _;
  }

  /// @notice Initializes the shared vault
  function initialize(
    string calldata _name,
    string calldata _symbol,
    address[4] calldata _tokens,
    uint256[4] calldata initialAmounts,
    address _owner,
    address _configManager
  ) public initializer {
    require(_configManager != address(0), ZeroAddress());
    require(_owner != address(0), ZeroAddress());

    __ERC20_init(_name, _symbol);
    __ERC20Permit_init(_name);

    configManager = ISharedConfigManager(_configManager);
    vaultOwner = _owner;
    vaultFactory = msg.sender;

    // Set up tokens
    uint8 count;
    for (uint256 i; i < 4;) {
      if (_tokens[i] != address(0)) {
        for (uint256 j; j < i;) {
          if (_tokens[j] == _tokens[i]) revert DuplicateToken();
          unchecked { j++; }
        }
        tokens[i] = _tokens[i];
        isVaultToken[_tokens[i]] = true;
        unchecked { count++; }
      }
      unchecked { i++; }
    }
    require(count >= 2, NoTokensConfigured());
    tokenCount = count;

    // Mint initial shares if tokens were deposited by factory
    uint256 refIndex = type(uint256).max;
    for (uint256 i; i < 4;) {
      if (initialAmounts[i] > 0) {
        require(tokens[i] != address(0), InvalidToken());
        if (refIndex == type(uint256).max) refIndex = i;
      }
      unchecked { i++; }
    }

    if (refIndex != type(uint256).max) {
      uint256 shares = initialAmounts[refIndex] * SHARES_PRECISION;
      _mint(_owner, shares);
      emit VaultDeposit(msg.sender, _owner, initialAmounts, shares);
    }
  }

  // ==================== Deposit / Withdraw ====================

  /// @notice Deposit tokens proportionally and receive shares
  /// @dev Share ratio is based on TOTAL balances (idle + LP positions valued by strategies)
  function deposit(uint256[4] calldata amounts, uint256 minShares)
    external
    override
    nonReentrant
    whenNotPaused
    returns (uint256 shares)
  {
    uint256 currentTotalSupply = totalSupply();
    uint256[4] memory totalBalances = _getTotalBalances();
    uint256[4] memory transferAmounts;

    if (currentTotalSupply == 0) {
      // First deposit — find reference token
      uint256 refIndex = type(uint256).max;
      for (uint256 i; i < 4;) {
        if (amounts[i] > 0) {
          require(tokens[i] != address(0), InvalidToken());
          if (refIndex == type(uint256).max) refIndex = i;
          transferAmounts[i] = amounts[i];
        }
        unchecked { i++; }
      }
      require(refIndex != type(uint256).max, InvalidAmount());
      shares = amounts[refIndex] * SHARES_PRECISION;
    } else {
      // Subsequent deposit — enforce proportional ratio based on total balances
      uint256 refIndex = type(uint256).max;
      for (uint256 i; i < 4;) {
        if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
          refIndex = i;
          break;
        }
        unchecked { i++; }
      }
      require(refIndex != type(uint256).max, InvalidAmount());

      shares = FullMath.mulDiv(amounts[refIndex], currentTotalSupply, totalBalances[refIndex]);
      transferAmounts[refIndex] = amounts[refIndex];

      for (uint256 i; i < 4;) {
        if (tokens[i] == address(0) || i == refIndex) {
          unchecked { i++; }
          continue;
        }
        if (totalBalances[i] == 0) {
          require(amounts[i] == 0, InvalidRatio());
        } else {
          uint256 expectedAmount = FullMath.mulDiv(shares, totalBalances[i], currentTotalSupply);
          require(amounts[i] >= expectedAmount, InvalidRatio());
          transferAmounts[i] = expectedAmount;
        }
        unchecked { i++; }
      }
    }

    require(shares >= minShares, InsufficientShares());

    for (uint256 i; i < 4;) {
      if (transferAmounts[i] > 0) {
        IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), transferAmounts[i]);
      }
      unchecked { i++; }
    }

    _mint(msg.sender, shares);

    emit VaultDeposit(vaultFactory, msg.sender, transferAmounts, shares);
  }

  /// @notice Withdraw proportional IDLE tokens by burning shares
  /// @dev Uses total balances for share ratio but only withdraws idle tokens.
  ///      If tokens are deployed to LP, withdrawer gets proportional idle only.
  function withdraw(uint256 shares, uint256[4] calldata minAmounts)
    external
    override
    nonReentrant
    returns (uint256[4] memory amounts)
  {
    require(shares > 0 && shares <= balanceOf(msg.sender), InsufficientShares());

    uint256 currentTotalSupply = totalSupply();
    _burn(msg.sender, shares);

    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0)) {
        uint256 idleBalance = IERC20(tokens[i]).balanceOf(address(this));
        amounts[i] = FullMath.mulDiv(shares, idleBalance, currentTotalSupply);
        require(amounts[i] >= minAmounts[i], InsufficientOutput());
        if (amounts[i] > 0) {
          IERC20(tokens[i]).safeTransfer(msg.sender, amounts[i]);
        }
      }
      unchecked { i++; }
    }

    emit VaultWithdraw(vaultFactory, msg.sender, amounts, shares);
  }

  // ==================== Strategy Execution ====================

  /// @notice Execute LP operation via whitelisted strategy (delegatecall)
  /// @dev Strategy returns position changes which the vault tracks with the strategy address
  function execute(address strategy, bytes calldata data)
    external
    payable
    override
    nonReentrant
    onlyAuthorized
    whenNotPaused
  {
    require(configManager.isWhitelistedTarget(strategy), InvalidStrategy(strategy));

    (bool success, bytes memory result) = strategy.delegatecall(abi.encodeCall(ISharedStrategy.execute, (data)));

    if (!success) {
      if (result.length == 0) revert StrategyCallFailed();
      assembly {
        revert(add(32, result), mload(result))
      }
    }

    // Process position changes returned by strategy
    if (result.length > 0) {
      ISharedStrategy.PositionChange[] memory changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
      for (uint256 i; i < changes.length;) {
        if (changes[i].isAdd) {
          _addPosition(strategy, changes[i].nfpm, changes[i].tokenId, changes[i].token0, changes[i].token1);
        } else {
          _removePosition(changes[i].nfpm, changes[i].tokenId);
        }
        unchecked { i++; }
      }
    }

    emit VaultExecute(vaultFactory, strategy, data);
  }

  // ==================== Swap ====================

  /// @notice Swap between vault tokens via whitelisted aggregator target
  function swap(
    address swapTarget,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    bytes calldata swapData
  ) external override nonReentrant onlyAuthorized whenNotPaused {
    require(isVaultToken[tokenIn], TokenNotConfigured());
    require(isVaultToken[tokenOut], TokenNotConfigured());
    require(configManager.isWhitelistedTarget(swapTarget), InvalidTarget(swapTarget));

    uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

    IERC20(tokenIn).safeResetAndApprove(swapTarget, amountIn);

    (bool success,) = swapTarget.call(swapData);
    require(success, SwapFailed());

    uint256 amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
    require(amountOut >= minAmountOut, InsufficientOutput());

    emit VaultSwap(vaultFactory, swapTarget, tokenIn, tokenOut, amountIn, amountOut);
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

  function getPosition(uint256 index)
    external
    view
    returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1)
  {
    Position memory pos = positions[index];
    return (pos.strategy, pos.nfpm, pos.tokenId, pos.token0, pos.token1);
  }

  function previewDeposit(uint256[4] calldata amounts) external view override returns (uint256 shares) {
    uint256 currentTotalSupply = totalSupply();
    uint256[4] memory totalBalances = _getTotalBalances();

    if (currentTotalSupply == 0) {
      for (uint256 i; i < 4;) {
        if (amounts[i] > 0) {
          return amounts[i] * SHARES_PRECISION;
        }
        unchecked { i++; }
      }
    } else {
      for (uint256 i; i < 4;) {
        if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
          return FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i]);
        }
        unchecked { i++; }
      }
    }
  }

  function previewWithdraw(uint256 _shares) external view override returns (uint256[4] memory amounts) {
    uint256 currentTotalSupply = totalSupply();
    if (currentTotalSupply == 0) return amounts;

    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0)) {
        uint256 idleBalance = IERC20(tokens[i]).balanceOf(address(this));
        amounts[i] = FullMath.mulDiv(_shares, idleBalance, currentTotalSupply);
      }
      unchecked { i++; }
    }
  }

  // ==================== Operator Sweep (non-vault tokens only) ====================

  function sweepTokens(address[] calldata _tokens, uint256[] calldata amounts, address to) external override onlyOperator {
    require(_tokens.length == amounts.length, InvalidAmount());
    for (uint256 i; i < _tokens.length;) {
      require(!isVaultToken[_tokens[i]], CannotSweepVaultToken());
      uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
      uint256 amount = amounts[i] > balance ? balance : amounts[i];
      IERC20(_tokens[i]).safeTransfer(to, amount);
      unchecked { i++; }
    }
  }

  function sweepNativeToken(uint256 amount, address to) external override onlyOperator {
    uint256 balance = address(this).balance;
    if (amount > balance) amount = balance;
    (bool success,) = to.call{ value: amount }("");
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

  function _getIdleBalances() internal view returns (uint256[4] memory balances) {
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0)) {
        balances[i] = IERC20(tokens[i]).balanceOf(address(this));
      }
      unchecked { i++; }
    }
  }

  /// @notice Total balances including idle tokens + LP position amounts valued by strategies
  function _getTotalBalances() internal view returns (uint256[4] memory balances) {
    balances = _getIdleBalances();

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen;) {
      Position memory pos = positions[p];

      // Delegate valuation to the strategy that created the position
      (uint256 amount0, uint256 amount1) = ISharedStrategy(pos.strategy).getPositionAmounts(pos.nfpm, pos.tokenId);

      // Map amounts back to vault token indices
      for (uint256 i; i < 4;) {
        if (tokens[i] == pos.token0) balances[i] += amount0;
        else if (tokens[i] == pos.token1) balances[i] += amount1;
        unchecked { i++; }
      }
      unchecked { p++; }
    }
  }

  receive() external payable { }
}
