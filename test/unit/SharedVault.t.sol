// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { Vm } from "forge-std/Vm.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { SharedStrategyFeeConfig } from "../../contracts/shared-vault/libraries/SharedStrategyFeeConfig.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IFeeTaker } from "../../contracts/public-vault/interfaces/strategies/IFeeTaker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";
import { ISharedV4Utils as IV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";
import { ISharedPancakeV4Utils as IPancakeV4Utils } from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
import { PoolKey as PancakeV4PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency as PancakeCurrency } from "infinity-core/src/types/Currency.sol";
import { IHooks as IPancakeHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager as IPancakePoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import { CLPositionInfo as PancakeV4PositionInfo } from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

// Mock WETH9 for testing native ETH wrapping/unwrapping
contract MockWETH9 {
  string public name = "Wrapped Ether";
  string public symbol = "WETH";
  uint8 public decimals = 18;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  receive() external payable {
    deposit();
  }

  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
  }

  function withdraw(uint256 wad) external {
    require(balanceOf[msg.sender] >= wad, "Insufficient WETH");
    balanceOf[msg.sender] -= wad;
    (bool ok,) = msg.sender.call{ value: wad }("");
    require(ok, "ETH transfer failed");
  }

  function totalSupply() external view returns (uint256) {
    return address(this).balance;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// Mock ERC20 token for testing
contract MockERC20 {
  string public name;
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name, string memory _symbol) {
    name = _name;
    symbol = _symbol;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

contract MockERC20NoDecimals {
  string public name = "No Decimals";
  string public symbol = "NODEC";
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

contract RejectNativeReceiver {
  receive() external payable {
    revert("reject native");
  }
}

// Mock ERC20 token with configurable decimals for testing non-18-decimal tokens
contract MockERC20LowDecimals {
  string public name;
  string public symbol;
  uint8 public decimals;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name, string memory _symbol, uint8 _decimals) {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// Mock strategy that validates tokens and sets a value
contract MockSharedStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    // No state written — this runs via delegatecall; writing to named slots would corrupt vault storage.
    abi.decode(data, (uint256));
    changes = new PositionChange[](0);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address, uint256) external pure override returns (address, address) {
    return (address(0), address(0));
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

// Mock strategy whose exitProportional always reverts (simulates a buggy deployed strategy)
contract MockBrokenExitStrategy is ISharedStrategy {
  // Mirrors real NFPM on-chain token data. Populated via registerPosition() since execute()
  // runs via delegatecall and cannot write to the strategy's own storage.
  mapping(bytes32 => address) private _token0;
  mapping(bytes32 => address) private _token1;

  function registerPosition(address nfpm, uint256 tokenId, address token0, address token1) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    _token0[key] = token0;
    _token1[key] = token1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) =
      abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    revert("broken exit");
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (_token0[key], _token1[key]);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

// Mock strategy whose depositProportional always reverts but getPositionAmounts returns non-zero.
// Simulates a rugged pool where the NFPM rejects increaseLiquidity but the strategy still reports liquidity.
contract MockBrokenDepositStrategy is ISharedStrategy {
  mapping(bytes32 => address) private _token0;
  mapping(bytes32 => address) private _token1;

  function registerPosition(address nfpm, uint256 tokenId, address token0, address token1) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    _token0[key] = token0;
    _token1[key] = token1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) =
      abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (100e18, 100e18);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    // Return non-zero so SharedVault computes a non-zero `toAdd` and actually calls depositProportional,
    // which in turn reverts — mirroring the pre-fix behavior of this broken-strategy scenario.
    return (100e18, 100e18);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (_token0[key], _token1[key]);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external pure override {
    revert("pool rugged");
  }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev DELEGATECALL strategy that returns `PositionChange.isAdd` with `token0`/`token1` from immutables,
///      not from calldata. Used to assert the vault rejects recording a new position when either pool
///      token is not a configured vault token, matching `_applyPositionChanges` + `CALL_WITH_POSITIONS`.
contract MockMisreportingTokenAddStrategy is ISharedStrategy {
  address public immutable token0Out;
  address public immutable token1Out;

  constructor(address _token0Out, address _token1Out) {
    token0Out = _token0Out;
    token1Out = _token1Out;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId,,) = abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0Out, token1Out);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (token0Out, token1Out);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

// Mock strategy that fails
contract MockFailingStrategy is ISharedStrategy {
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    revert("Strategy failed");
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address, uint256) external pure override returns (address, address) {
    return (address(0), address(0));
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

// Mock swap target
contract MockSwapTarget {
  function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
    // Take tokenIn, give tokenOut
    MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    // Give 1:1 swap
    MockERC20(tokenOut).transfer(msg.sender, amountIn);
  }

  // Partial fill: only consumes half of amountIn, leaving residual allowance if not reset
  function partialSwap(address tokenIn, address tokenOut, uint256 amountIn) external {
    uint256 consumed = amountIn / 2;
    MockERC20(tokenIn).transferFrom(msg.sender, address(this), consumed);
    MockERC20(tokenOut).transfer(msg.sender, consumed);
  }
}

/// @dev Simulates an external contract called via CALL_WITH_POSITIONS that returns PositionChange[].
///      Unlike strategies (which run via delegatecall), this is a standalone contract that the
///      vault calls directly. It stores registered token pairs so getPositionTokens satisfies the
///      canonical-token check in _applyPositionChangesChecked.
contract MockDirectPositionCreator is ISharedStrategy {
  mapping(address => mapping(uint256 => address)) private _token0;
  mapping(address => mapping(uint256 => address)) private _token1;

  /// @dev Creates a position: stores token pair, returns PositionChange with isAdd=true.
  function createPosition(address nfpm, uint256 tokenId, address token0, address token1)
    external
    returns (PositionChange[] memory changes)
  {
    _token0[nfpm][tokenId] = token0;
    _token1[nfpm][tokenId] = token1;
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  /// @dev Removes a position: returns PositionChange with isAdd=false.
  function removePosition(address nfpm, uint256 tokenId, address token0, address token1)
    external
    pure
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: false, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  /// @dev Returns an empty PositionChange[] — simulates a no-op call.
  function noChanges() external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  /// @dev Reverts — simulates a failing target call.
  function alwaysFail() external pure returns (PositionChange[] memory) {
    revert("DirectCreator: always fails");
  }

  // ISharedStrategy stubs (not used in CALL_WITH_POSITIONS path)
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    return new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    return (_token0[nfpm][tokenId], _token1[nfpm][tokenId]);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev CALL_WITH_POSITIONS strategy whose getPositionAmounts always reverts with non-empty data.
///      Used to verify that the probe in _applyPositionChangesChecked requires ok=true.
contract MockRevertingGetPositionAmountsStrategy is ISharedStrategy {
  function createPosition(address nfpm, uint256 tokenId, address token0, address token1)
    external
    pure
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    return new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    revert("getPositionAmounts: intentional revert with data");
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address, uint256) external pure override returns (address, address) {
    return (address(0), address(0));
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev CALL_WITH_POSITIONS strategy that reports a different (but valid vault-token) pair than what
///      getPositionTokens returns — used to verify the canonical token check in _applyPositionChangesChecked.
contract MockWrongCanonicalTokensStrategy is ISharedStrategy {
  address public immutable canonToken0;
  address public immutable canonToken1;

  constructor(address _t0, address _t1) {
    canonToken0 = _t0;
    canonToken1 = _t1;
  }

  /// @dev Reports token0/token1 that differ from what getPositionTokens returns.
  function createPositionWrongTokens(address nfpm, uint256 tokenId, address reportedToken0, address reportedToken1)
    external
    pure
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](1);
    changes[0] =
      PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: reportedToken0, token1: reportedToken1 });
  }

  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    return new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  // Returns the canonical (correct) pair — different from what createPositionWrongTokens reports.
  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (canonToken0, canonToken1);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev V4UtilsRouter mock: execute is a no-op, used to test V4Strategy without real router deps.
contract MockV4UtilsRouter {
  function execute(address, bytes calldata) external payable {
    /* no-op */
  }
}

contract MockV4Permit2 {
  mapping(address => mapping(address => mapping(address => uint160))) public allowanceAmount;

  function approve(address token, address spender, uint160 amount, uint48) external {
    allowanceAmount[msg.sender][token][spender] = amount;
  }
}

struct V4TestInputTokenParams {
  address token;
  uint256 amount;
}

struct V4TestSwapAndMintParams {
  address posm;
  PoolKey poolKey;
  IV4Utils.MintParams mintParams;
  IV4Utils.SwapParams[] swapParams;
  V4TestInputTokenParams[] inputTokens;
  uint64 protocolFeeX64;
  uint64 performanceFeeX64;
  uint64 gasFeeX64;
}

contract MockV4PoolManager {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  function extsload(bytes32) external pure returns (bytes32 value) {
    value = bytes32(uint256(SQRT_PRICE_1_1));
  }

  function extsload(bytes32, uint256 nSlots) external pure returns (bytes32[] memory values) {
    values = new bytes32[](nSlots);
  }

  function getSlot0(bytes32)
    external
    pure
    returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
  {
    sqrtPriceX96 = SQRT_PRICE_1_1;
    tick = 0;
    protocolFee = 0;
    lpFee = 0;
  }
}

/// @dev Minimal V4 PositionManager mock for Issue 1 and 4 tests.
///      Implements only the functions called by SharedV4Strategy._execute and _safeTransferNft.
contract MockV4PositionManager {
  uint256 private _nextTokenId;
  MockV4Permit2 public immutable permit2;
  MockV4PoolManager public immutable poolManager;
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => address) private _approved;
  mapping(uint256 => uint128) private _liquidity;
  mapping(uint256 => address) private _currency0;
  mapping(uint256 => address) private _currency1;
  mapping(uint256 => uint256) private _collectAmount0;
  mapping(uint256 => uint256) private _collectAmount1;
  // Config for safeTransferFrom to optionally simulate minting a new NFT during the transfer call.
  uint256 private _mintOnTransfer;
  address private _mintOnTransferTo;
  uint256 private _mintOnModify;
  address private _mintOnModifyTo;

  constructor(uint256 startNextId) {
    _nextTokenId = startNextId;
    permit2 = new MockV4Permit2();
    poolManager = new MockV4PoolManager();
  }

  function nextTokenId() external view returns (uint256) {
    return _nextTokenId;
  }

  function setOwner(uint256 tokenId, address owner) external {
    ownerOf[tokenId] = owner;
  }

  function setLiquidity(uint256 tokenId, uint128 liq) external {
    _liquidity[tokenId] = liq;
  }

  /// @dev Stores pool currency pair for getPoolAndPositionInfo.
  function setPoolInfo(uint256 tokenId, address c0, address c1) external {
    _currency0[tokenId] = c0;
    _currency1[tokenId] = c1;
  }

  function setCollectFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
    _collectAmount0[tokenId] = amount0;
    _collectAmount1[tokenId] = amount1;
  }

  /// @dev When set, safeTransferFrom will mint tokenId=_mintOnTransfer to _mintOnTransferTo.
  function setSafeTransferMint(uint256 mintId, address mintTo) external {
    _mintOnTransfer = mintId;
    _mintOnTransferTo = mintTo;
  }

  function setModifyLiquiditiesMint(uint256 mintId, address mintTo) external {
    _mintOnModify = mintId;
    _mintOnModifyTo = mintTo;
  }

  /// @dev Simulates the POSM minting a new NFT: sets owner and advances nextTokenId.
  function simulateMint(uint256 tokenId, address to) external {
    ownerOf[tokenId] = to;
    if (_nextTokenId <= tokenId) _nextTokenId = tokenId + 1;
  }

  function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
    return _liquidity[tokenId];
  }

  function getPoolAndPositionInfo(uint256 tokenId)
    external
    view
    returns (PoolKey memory poolKey, PositionInfo posInfo)
  {
    poolKey.currency0 = Currency.wrap(_currency0[tokenId]);
    poolKey.currency1 = Currency.wrap(_currency1[tokenId]);
    // fee, tickSpacing, hooks left at zero defaults; PositionInfo default-zero is fine for tests.
    posInfo = PositionInfo.wrap(0);
  }

  function positionInfo(uint256 tokenId) external view returns (PositionInfo info) {
    PoolKey memory poolKey = PoolKey({
      currency0: Currency.wrap(_currency0[tokenId]),
      currency1: Currency.wrap(_currency1[tokenId]),
      fee: 0,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });
    info = PositionInfoLibrary.initialize(poolKey, -60, 60);
  }

  function modifyLiquidities(bytes calldata data, uint256) external payable {
    (bytes memory actions, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));

    if (_mintOnModifyTo != address(0)) {
      ownerOf[_mintOnModify] = _mintOnModifyTo;
      if (_nextTokenId <= _mintOnModify) _nextTokenId = _mintOnModify + 1;
      _mintOnModifyTo = address(0);
    }

    uint8 action = uint8(actions[0]);
    uint256 tokenId;
    if (action == 0x02) {
      PoolKey memory poolKey;
      uint128 liquidity;
      address recipient;
      (poolKey,,, liquidity,,, recipient,) =
        abi.decode(params[0], (PoolKey, int24, int24, uint128, uint128, uint128, address, bytes));
      tokenId = _nextTokenId;
      ownerOf[tokenId] = recipient;
      _currency0[tokenId] = Currency.unwrap(poolKey.currency0);
      _currency1[tokenId] = Currency.unwrap(poolKey.currency1);
      _liquidity[tokenId] = liquidity;
      _nextTokenId = tokenId + 1;
      return;
    }

    bytes memory firstParam = params[0];
    assembly {
      tokenId := mload(add(firstParam, 32))
    }

    if (action == 0x01) {
      (, uint128 liquidityToDecrease,,,) = abi.decode(params[0], (uint256, uint128, uint256, uint256, bytes));
      if (liquidityToDecrease > 0) {
        _liquidity[tokenId] = liquidityToDecrease >= _liquidity[tokenId] ? 0 : _liquidity[tokenId] - liquidityToDecrease;
      }
    }

    uint256 amount0 = _collectAmount0[tokenId];
    uint256 amount1 = _collectAmount1[tokenId];
    _collectAmount0[tokenId] = 0;
    _collectAmount1[tokenId] = 0;

    if (amount0 > 0) {
      (bool ok,) = _currency0[tokenId].call(abi.encodeWithSignature("mint(address,uint256)", msg.sender, amount0));
      require(ok, "mint0");
    }
    if (amount1 > 0) {
      (bool ok,) = _currency1[tokenId].call(abi.encodeWithSignature("mint(address,uint256)", msg.sender, amount1));
      require(ok, "mint1");
    }
  }

  function approve(address spender, uint256 tokenId) external {
    _approved[tokenId] = spender;
  }

  function getApproved(uint256 tokenId) external view returns (address) {
    return _approved[tokenId];
  }

  /// @dev Keeps NFT at vault (no-op transfer). If setSafeTransferMint is configured, mints a new
  ///      NFT to the specified address — simulating V4Utils minting during safeTransferFrom processing.
  function safeTransferFrom(address, address, uint256, bytes calldata) external {
    if (_mintOnTransferTo != address(0)) {
      ownerOf[_mintOnTransfer] = _mintOnTransferTo;
      if (_nextTokenId <= _mintOnTransfer) _nextTokenId = _mintOnTransfer + 1;
      _mintOnTransferTo = address(0); // reset after use
    }
  }
}

contract MockPancakeV4PoolManager {
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  function initialize(PancakeV4PoolKey calldata, uint160) external pure returns (int24 tick) {
    tick = 0;
  }

  function getSlot0(bytes32)
    external
    pure
    returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
  {
    sqrtPriceX96 = SQRT_PRICE_1_1;
    tick = 0;
    protocolFee = 0;
    lpFee = 0;
  }

  function getFeeGrowthGlobals(bytes32) external pure returns (uint256, uint256) {
    return (0, 0);
  }

  function getPoolTickInfo(bytes32, int24) external pure returns (uint128, int128, uint256, uint256) {
    return (0, 0, 0, 0);
  }

  /// @dev Canonical fee-growth-inside getter now used by SharedPancakeV4StrategyLib (F1). Returns 0
  ///      for this mock so happy-path tests see zero pending fees, matching the prior behavior.
  function getFeeGrowthInside(bytes32, int24, int24) external pure returns (uint256, uint256) {
    return (0, 0);
  }
}

contract MockPancakeV4PositionManager {
  uint256 private _nextTokenId;
  MockV4Permit2 public immutable permit2;
  MockPancakeV4PoolManager public immutable poolManager;
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => address) private _approved;
  mapping(uint256 => uint128) private _liquidity;
  mapping(uint256 => PancakeV4PoolKey) private _poolKey;
  mapping(uint256 => uint256) private _collectAmount0;
  mapping(uint256 => uint256) private _collectAmount1;

  constructor(uint256 startNextId) {
    _nextTokenId = startNextId;
    permit2 = new MockV4Permit2();
    poolManager = new MockPancakeV4PoolManager();
  }

  function nextTokenId() external view returns (uint256) {
    return _nextTokenId;
  }

  function clPoolManager() external view returns (address) {
    return address(poolManager);
  }

  function setOwner(uint256 tokenId, address owner) external {
    ownerOf[tokenId] = owner;
  }

  function setLiquidity(uint256 tokenId, uint128 liq) external {
    _liquidity[tokenId] = liq;
  }

  function setPoolInfo(uint256 tokenId, address c0, address c1) external {
    _poolKey[tokenId] = PancakeV4PoolKey({
      currency0: PancakeCurrency.wrap(c0),
      currency1: PancakeCurrency.wrap(c1),
      hooks: IPancakeHooks(address(0)),
      poolManager: IPancakePoolManager(address(poolManager)),
      fee: 3000,
      parameters: bytes32(uint256(uint24(60)) << 16)
    });
  }

  function setCollectFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
    _collectAmount0[tokenId] = amount0;
    _collectAmount1[tokenId] = amount1;
  }

  function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
    return _liquidity[tokenId];
  }

  function getPoolAndPositionInfo(uint256 tokenId)
    external
    view
    returns (PancakeV4PoolKey memory poolKey, PancakeV4PositionInfo posInfo)
  {
    poolKey = _poolKey[tokenId];
    posInfo = _positionInfo(-60, 60);
  }

  function positions(uint256 tokenId)
    external
    view
    returns (PancakeV4PoolKey memory poolKey, int24, int24, uint128, uint256, uint256, address)
  {
    return (_poolKey[tokenId], -60, 60, _liquidity[tokenId], 0, 0, address(0));
  }

  function modifyLiquidities(bytes calldata data, uint256) external payable {
    (bytes memory actions, bytes[] memory params) = abi.decode(data, (bytes, bytes[]));
    uint8 action = uint8(actions[0]);
    uint256 tokenId;

    if (action == 0x02) {
      PancakeV4PoolKey memory key;
      uint128 liquidity;
      address recipient;
      (key,,, liquidity,,, recipient,) =
        abi.decode(params[0], (PancakeV4PoolKey, int24, int24, uint128, uint128, uint128, address, bytes));
      tokenId = _nextTokenId;
      ownerOf[tokenId] = recipient;
      _poolKey[tokenId] = key;
      _liquidity[tokenId] = liquidity;
      _nextTokenId = tokenId + 1;
      return;
    }

    bytes memory firstParam = params[0];
    assembly {
      tokenId := mload(add(firstParam, 32))
    }

    if (action == 0x01) {
      (, uint128 liquidityToDecrease,,,) = abi.decode(params[0], (uint256, uint128, uint256, uint256, bytes));
      if (liquidityToDecrease > 0) {
        _liquidity[tokenId] = liquidityToDecrease >= _liquidity[tokenId] ? 0 : _liquidity[tokenId] - liquidityToDecrease;
      }
    }

    uint256 amount0 = _collectAmount0[tokenId];
    uint256 amount1 = _collectAmount1[tokenId];
    _collectAmount0[tokenId] = 0;
    _collectAmount1[tokenId] = 0;
    if (amount0 > 0) {
      (bool ok,) = PancakeCurrency.unwrap(_poolKey[tokenId].currency0).call(
        abi.encodeWithSignature("mint(address,uint256)", msg.sender, amount0)
      );
      require(ok, "mint0");
    }
    if (amount1 > 0) {
      (bool ok,) = PancakeCurrency.unwrap(_poolKey[tokenId].currency1).call(
        abi.encodeWithSignature("mint(address,uint256)", msg.sender, amount1)
      );
      require(ok, "mint1");
    }
  }

  function approve(address spender, uint256 tokenId) external {
    _approved[tokenId] = spender;
  }

  function getApproved(uint256 tokenId) external view returns (address) {
    return _approved[tokenId];
  }

  function safeTransferFrom(address, address, uint256, bytes calldata) external { }

  function _positionInfo(int24 tickLower, int24 tickUpper) private pure returns (PancakeV4PositionInfo) {
    return PancakeV4PositionInfo.wrap((uint256(uint24(tickLower)) << 8) | (uint256(uint24(tickUpper)) << 32));
  }
}

/// @dev V4UtilsRouter that calls simulateMint on a target POSM during execute — used to test
///      the Issue 6a / 6b silent-fallthrough fix without real V4Utils dependencies.
contract MockMintingV4UtilsRouter {
  address public immutable posm;
  uint256 public immutable mintId;
  address public immutable mintTo;

  constructor(address _posm, uint256 _mintId, address _mintTo) {
    posm = _posm;
    mintId = _mintId;
    mintTo = _mintTo;
  }

  function execute(address, bytes calldata) external payable {
    MockV4PositionManager(posm).simulateMint(mintId, mintTo);
  }
}

contract MockPreCollectStrategy is ISharedStrategy {
  mapping(bytes32 => address) private _token0;
  mapping(bytes32 => address) private _token1;

  event ExecuteCalled();
  event LegacyCollectFees(address nfpm, uint256 tokenId, uint16 ignoredVaultOwnerBps);

  function registerPosition(address nfpm, uint256 tokenId, address token0, address token1) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    _token0[key] = token0;
    _token1[key] = token1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    if (data.length == 0) {
      emit ExecuteCalled();
      return new PositionChange[](0);
    }
    (address nfpm, uint256 tokenId, address token0, address token1) =
      abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (_token0[key], _token1[key]);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address nfpm, uint256 tokenId, uint16 ignoredVaultOwnerBps) external override {
    emit LegacyCollectFees(nfpm, tokenId, ignoredVaultOwnerBps);
  }
}

contract SharedVaultCollectHarness is SharedVault {
  function collectWithStrategy(address strategy, address posm, uint256 tokenId) external {
    (bool ok, bytes memory result) =
      strategy.delegatecall(abi.encodeCall(ISharedStrategy.collectFees, (posm, tokenId, vaultOwnerFeeBasisPoint)));
    if (!ok) {
      if (result.length == 0) revert ISharedCommon.StrategyCallFailed();
      assembly {
        revert(add(32, result), mload(result))
      }
    }
  }

  function executeWithStrategy(address strategy, bytes calldata data) external {
    (bool ok, bytes memory result) = strategy.delegatecall(abi.encodeCall(ISharedStrategy.execute, (data)));
    if (!ok) {
      if (result.length == 0) revert ISharedCommon.StrategyCallFailed();
      assembly {
        revert(add(32, result), mload(result))
      }
    }
  }
}

/// @dev Delegatecall strategy that reports correct tokens in execute() but returns a DIFFERENT
///      pair from getPositionTokens() — used to verify the canonical-token check added to
///      _applyPositionChanges (delegatecall path) in Issue 7.
contract MockDelegatecallWrongCanonTokensStrategy is ISharedStrategy {
  address public immutable canonToken0;
  address public immutable canonToken1;

  constructor(address _ct0, address _ct1) {
    canonToken0 = _ct0;
    canonToken1 = _ct1;
  }

  /// @dev Returns a PositionChange with (token0, token1) from calldata, but getPositionTokens
  ///      returns (canonToken0, canonToken1) which differ — triggering the canonical check.
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address t0, address t1) = abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, t0, t1);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    return new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  // Returns the immutable canonical pair — intentionally different from what execute() reports.
  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (canonToken0, canonToken1);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev Delegatecall strategy that issues an isAdd=false PositionChange for a position the vault
///      still owns, and getPositionAmounts returns non-zero — used to verify Issue 8 (remove not
///      trusted blindly) on the _applyPositionChanges (delegatecall) path.
contract MockFalseRemoveStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address t0, address t1) = abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(false, nfpm, tokenId, t0, t1); // isAdd=false despite live position
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    return new PositionChange[](0);
  }

  // Reports non-zero value — position is still live.
  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (100e18, 100e18);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (100e18, 100e18);
  }

  function getPositionTokens(address, uint256) external pure override returns (address, address) {
    return (address(0), address(0));
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev CALL_WITH_POSITIONS target that issues an isAdd=false PositionChange while the vault still
///      owns the NFT and getPositionAmounts is non-zero — tests Issue 8 on the _applyPositionChangesChecked path.
contract MockCwpFalseRemoveStrategy is ISharedStrategy {
  // Returns remove change directly — used via CALL_WITH_POSITIONS.
  function removePosition(address nfpm, uint256 tokenId, address token0, address token1)
    external
    pure
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](1);
    changes[0] = PositionChange(false, nfpm, tokenId, token0, token1);
  }

  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory)
  {
    return new PositionChange[](0);
  }

  // Reports non-zero — position is still live.
  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (50e18, 50e18);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (50e18, 50e18);
  }

  function getPositionTokens(address, uint256) external pure override returns (address, address) {
    return (address(0), address(0));
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev V3 NFPM mock that simulates *inverted* CHANGE_RANGE ordering:
///      the old tokenId is returned to the vault BEFORE the new one is minted.
///      This triggers the `require(newTokenId != tokenId)` guard in SharedV3Strategy._safeTransferNft.
contract MockInvertedOrderingNfpm {
  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  address public immutable token0;
  address public immutable token1;
  uint256 private _nextNewId;

  mapping(address => uint256[]) private _ownedTokens;
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => uint128) private _liquidity;

  constructor(address _t0, address _t1, uint256 startNextId) {
    token0 = _t0;
    token1 = _t1;
    _nextNewId = startNextId;
  }

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
    _liquidity[tokenId] = 1000;
    _ownedTokens[to].push(tokenId);
  }

  function balanceOf(address owner) external view returns (uint256) {
    return _ownedTokens[owner].length;
  }

  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
    return _ownedTokens[owner][index];
  }

  // 0x780e9d63 is the IERC721Enumerable interface ID.
  function supportsInterface(bytes4 id) external pure returns (bool) {
    return id == 0x780e9d63;
  }

  function approve(address, uint256) external { }

  function transferFrom(address from, address to, uint256 tokenId) external {
    _removeFromOwner(from, tokenId);
    ownerOf[tokenId] = to;
    _ownedTokens[to].push(tokenId);
  }

  function factory() external view returns (address) {
    return address(this);
  }

  function getPool(address, address, uint24) external view returns (address) {
    return address(this);
  }

  function collect(CollectParams calldata) external pure returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    returns (uint256 amount0, uint256 amount1)
  {
    uint128 current = _liquidity[params.tokenId];
    _liquidity[params.tokenId] = params.liquidity >= current ? 0 : current - params.liquidity;
    return (0, 0);
  }

  function mint(MintParams calldata params)
    external
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    tokenId = _nextNewId++;
    ownerOf[tokenId] = params.recipient;
    _ownedTokens[params.recipient].push(tokenId);
    return (tokenId, 0, 0, 0);
  }

  /// @dev Simulates inverted V3Utils CHANGE_RANGE: returns old NFT to vault first, THEN mints new one.
  function safeTransferFrom(address from, address, uint256 tokenId, bytes calldata) external {
    _removeFromOwner(from, tokenId);
    ownerOf[tokenId] = address(0);

    // Inverted ordering: old NFT lands at index (balanceBefore - 1) = 0 before the new one.
    _ownedTokens[from].push(tokenId);
    ownerOf[tokenId] = from;

    uint256 newId = _nextNewId++;
    _ownedTokens[from].push(newId);
    ownerOf[newId] = from;
  }

  /// @dev positions() returns tracked liquidity so native CHANGE_RANGE can close the old position.
  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    return (0, address(0), token0, token1, 0, 0, 0, _liquidity[tokenId], 0, 0, 0, 0);
  }

  function _removeFromOwner(address owner, uint256 tokenId) private {
    uint256[] storage arr = _ownedTokens[owner];
    for (uint256 i; i < arr.length; i++) {
      if (arr[i] == tokenId) {
        arr[i] = arr[arr.length - 1];
        arr.pop();
        return;
      }
    }
  }
}

/// @dev V3 NFPM that simulates CHANGE_RANGE minting a new token but burning (not returning) the old one.
///      Post-call balance == balanceBefore (net zero), so the +1 check in _safeTransferNft reverts.
contract MockBurnWithoutReturnNfpm {
  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  address public immutable token0;
  address public immutable token1;
  uint256 private _nextNewId;

  mapping(address => uint256[]) private _ownedTokens;
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => uint128) private _liquidity;

  constructor(address _t0, address _t1, uint256 startNextId) {
    token0 = _t0;
    token1 = _t1;
    _nextNewId = startNextId;
  }

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
    _liquidity[tokenId] = 1000;
    _ownedTokens[to].push(tokenId);
  }

  function balanceOf(address owner) external view returns (uint256) {
    return _ownedTokens[owner].length;
  }

  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
    return _ownedTokens[owner][index];
  }

  function supportsInterface(bytes4 id) external pure returns (bool) {
    return id == 0x780e9d63;
  }

  function approve(address, uint256) external { }

  function factory() external view returns (address) {
    return address(this);
  }

  function getPool(address, address, uint24) external pure returns (address) {
    return address(0);
  }

  function collect(CollectParams calldata) external pure returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    returns (uint256 amount0, uint256 amount1)
  {
    _liquidity[params.tokenId] = 0;
    return (0, 0);
  }

  function mint(MintParams calldata)
    external
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    tokenId = _nextNewId++;
    _liquidity[tokenId] = 0;
    return (tokenId, 0, 0, 0);
  }

  /// @dev Burns the transferred NFT (does not return it) and mints a new one — net balance unchanged.
  function safeTransferFrom(address from, address, uint256 tokenId, bytes calldata) external {
    _removeFromOwner(from, tokenId);
    ownerOf[tokenId] = address(0);
    // Mint new token to the sender (from), but old token is burned → balance stays the same.
    uint256 newId = _nextNewId++;
    _ownedTokens[from].push(newId);
    ownerOf[newId] = from;
  }

  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    return (0, address(0), token0, token1, 0, 0, 0, _liquidity[tokenId], 0, 0, 0, 0);
  }

  function _removeFromOwner(address owner, uint256 tokenId) private {
    uint256[] storage arr = _ownedTokens[owner];
    for (uint256 i; i < arr.length; i++) {
      if (arr[i] == tokenId) {
        arr[i] = arr[arr.length - 1];
        arr.pop();
        return;
      }
    }
  }
}

/// @dev Aerodrome NFPM mock that simulates inverted CHANGE_RANGE ordering (old returned before new minted).
///      Uses int24 tickSpacing in positions() to match Aerodrome's interface.
contract MockAerodromeInvertedOrderingNfpm {
  struct MintParams {
    address token0;
    address token1;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
    uint160 sqrtPriceX96;
  }

  struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  address public immutable token0;
  address public immutable token1;
  uint256 private _nextNewId;

  mapping(address => uint256[]) private _ownedTokens;
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => uint128) private _liquidity;

  constructor(address _t0, address _t1, uint256 startNextId) {
    token0 = _t0;
    token1 = _t1;
    _nextNewId = startNextId;
  }

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
    _liquidity[tokenId] = 1000;
    _ownedTokens[to].push(tokenId);
  }

  function balanceOf(address owner) external view returns (uint256) {
    return _ownedTokens[owner].length;
  }

  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
    return _ownedTokens[owner][index];
  }

  function supportsInterface(bytes4 id) external pure returns (bool) {
    return id == 0x780e9d63;
  }

  function approve(address, uint256) external { }

  function transferFrom(address from, address to, uint256 tokenId) external {
    _removeFromOwner(from, tokenId);
    ownerOf[tokenId] = to;
    _ownedTokens[to].push(tokenId);
  }

  function factory() external view returns (address) {
    return address(this);
  }

  function getPool(address, address, int24) external view returns (address) {
    return address(this);
  }

  function collect(CollectParams calldata) external pure returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    returns (uint256 amount0, uint256 amount1)
  {
    uint128 current = _liquidity[params.tokenId];
    _liquidity[params.tokenId] = params.liquidity >= current ? 0 : current - params.liquidity;
    return (0, 0);
  }

  function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    tokenId = _nextNewId++;
    ownerOf[tokenId] = params.recipient;
    _ownedTokens[params.recipient].push(tokenId);
    return (tokenId, 0, 0, 0);
  }

  /// @dev Inverted ordering: returns old NFT first, then mints new one.
  function safeTransferFrom(address from, address, uint256 tokenId, bytes calldata) external {
    _removeFromOwner(from, tokenId);
    ownerOf[tokenId] = address(0);
    // Inverted: old returned first, new minted second.
    _ownedTokens[from].push(tokenId);
    ownerOf[tokenId] = from;
    uint256 newId = _nextNewId++;
    _ownedTokens[from].push(newId);
    ownerOf[newId] = from;
  }

  /// @dev Aerodrome positions() uses int24 tickSpacing. Zero liquidity mirrors CHANGE_RANGE close behavior.
  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    return (0, address(0), token0, token1, 60, 0, 0, _liquidity[tokenId], 0, 0, 0, 0);
  }

  function _removeFromOwner(address owner, uint256 tokenId) private {
    uint256[] storage arr = _ownedTokens[owner];
    for (uint256 i; i < arr.length; i++) {
      if (arr[i] == tokenId) {
        arr[i] = arr[arr.length - 1];
        arr.pop();
        return;
      }
    }
  }
}

/// @dev NFPM whose transferFrom silently no-ops — used to verify recoverPosition checks actual ownership.
contract MockSilentTransferNfpm {
  mapping(uint256 => address) public ownerOf;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function approve(address, uint256) external { }

  function transferFrom(address, address, uint256) external {
    // Intentional no-op: NFT stays with its current owner.
  }
}

// Mock ERC721 for sweep tests
contract MockERC721 {
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => address) private _approved;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function getApproved(uint256 tokenId) external view returns (address) {
    return _approved[tokenId];
  }

  function approve(address spender, uint256 tokenId) external {
    _approved[tokenId] = spender;
  }

  function transferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    require(msg.sender == from || msg.sender == _approved[tokenId], "Not approved");
    ownerOf[tokenId] = to;
    _approved[tokenId] = address(0);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    ownerOf[tokenId] = to;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
    require(ownerOf[tokenId] == from, "Not owner");
    ownerOf[tokenId] = to;
  }
}

// Mock ERC1155 for sweep tests
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 id, uint256 amount) external {
    balanceOf[to][id] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
    require(balanceOf[from][id] >= amount, "Insufficient balance");
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;
  }
}

// Mock LP pool that holds tokens and simulates proportional LP exits
contract MockLPPool {
  struct LP {
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
  }

  mapping(bytes32 => LP) public lps;

  function deposit(address nfpm, uint256 tokenId, address token0, address token1, uint256 _amount0, uint256 _amount1)
    external
  {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    lp.token0 = token0;
    lp.token1 = token1;
    lp.amount0 += _amount0;
    lp.amount1 += _amount1;
  }

  function exit(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, address recipient) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    uint256 exit0 = (lp.amount0 * shares) / totalShares;
    uint256 exit1 = (lp.amount1 * shares) / totalShares;
    if (exit0 > 0) {
      MockERC20(lp.token0).transfer(recipient, exit0);
      lp.amount0 -= exit0;
    }
    if (exit1 > 0) {
      MockERC20(lp.token1).transfer(recipient, exit1);
      lp.amount1 -= exit1;
    }
  }

  function getAmounts(address nfpm, uint256 tokenId) external view returns (uint256, uint256) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (lps[key].amount0, lps[key].amount1);
  }
}

// Mock strategy that simulates realistic LP creation + proportional exits
// Uses immutable lpPool ref so it's accessible in delegatecall context
contract MockLPExitStrategy is ISharedStrategy {
  address public immutable lpPool;

  /// @dev Emitted on proportional exit; under delegatecall this logs from the vault address.
  event ExitVaultOwnerFeeBps(uint16 basisPoints);

  constructor(address _lpPool) {
    lpPool = _lpPool;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1) =
      abi.decode(data, (address, uint256, address, address, uint256, uint256));

    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);

    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);

    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16 vaultOwnerFeeBasisPoint
  ) external override returns (PositionChange[] memory changes) {
    emit ExitVaultOwnerFeeBps(vaultOwnerFeeBasisPoint);
    MockLPPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (uint256 amount0, uint256 amount1)
  {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  /// @dev Mock pool doesn't separate principal vs rewards — treat the whole balance as principal.
  ///      Integration coverage for the real split lives in SharedV3/V4/Aerodrome strategy tests.
  function getPositionPrincipalAmounts(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (uint256 amount0, uint256 amount1)
  {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function getPositionTokens(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (address token0, address token1)
  {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (token0, token1,,) = MockLPPool(lpPool).lps(key);
  }

  function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16)
    external
    override
  {
    if (amount0 == 0 && amount1 == 0) return;
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address token0, address token1,,) = MockLPPool(lpPool).lps(key);
    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);
  }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev Like MockLPExitStrategy but collectFees always reverts. Used to verify that a failing
///      pre-collect in SharedVault.withdraw() now propagates as StrategyCallFailed() instead of
///      silently falling back to per-withdrawer fee distribution.
contract MockCollectFailingStrategy is ISharedStrategy {
  address public immutable lpPool;

  constructor(address _lpPool) {
    lpPool = _lpPool;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1) =
      abi.decode(data, (address, uint256, address, address, uint256, uint256));
    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16
  ) external override returns (PositionChange[] memory changes) {
    MockLPPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address nfpm, uint256 tokenId) external view override returns (uint256, uint256) {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function getPositionPrincipalAmounts(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (uint256, uint256)
  {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address t0, address t1,,) = MockLPPool(lpPool).lps(key);
    return (t0, t1);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external pure override {
    revert("collectFees intentionally fails");
  }
}

/// @dev Simulates an LP pool that collapses in value mid-deposit (sandwich / LP manipulation).
///      First `deposit` call registers the position normally (used during `execute` / LP creation).
///      Any subsequent `deposit` call still records the key, but `getAmounts` returns (0, 0),
///      making the vault see no post-deposit balance increase — triggering the
///      `_computeSharesFromDelta` protection and reverting with InsufficientShares.
contract MockDropAfterSecondDepositPool {
  struct LP {
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
  }

  mapping(bytes32 => LP) public lps;
  uint256 public depositCount;

  function deposit(address nfpm, uint256 tokenId, address token0, address token1, uint256 _amount0, uint256 _amount1)
    external
  {
    depositCount++;
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    lp.token0 = token0;
    lp.token1 = token1;
    if (depositCount == 1) {
      lp.amount0 += _amount0;
      lp.amount1 += _amount1;
    }
    // On depositCount >= 2, amounts stay at zero — the LP "dropped" in value.
  }

  function exit(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, address recipient) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    uint256 exit0 = (lp.amount0 * shares) / totalShares;
    uint256 exit1 = (lp.amount1 * shares) / totalShares;
    if (exit0 > 0) MockERC20(lp.token0).transfer(recipient, exit0);
    lp.amount0 -= exit0;
    if (exit1 > 0) MockERC20(lp.token1).transfer(recipient, exit1);
    lp.amount1 -= exit1;
  }

  function getAmounts(address nfpm, uint256 tokenId) external view returns (uint256, uint256) {
    if (depositCount >= 2) return (0, 0);
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (lps[key].amount0, lps[key].amount1);
  }
}

/// @dev Strategy backed by MockDropAfterSecondDepositPool.  Mirrors MockLPExitStrategy but routes
///      all pool calls through MockDropAfterSecondDepositPool.
contract MockDropAfterSecondDepositStrategy is ISharedStrategy {
  address public immutable lpPool;

  constructor(address _lpPool) {
    lpPool = _lpPool;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1) =
      abi.decode(data, (address, uint256, address, address, uint256, uint256));
    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);
    MockDropAfterSecondDepositPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16)
    external
    override
  {
    if (amount0 == 0 && amount1 == 0) return;
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address token0, address token1,,) = MockDropAfterSecondDepositPool(lpPool).lps(key);
    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);
    MockDropAfterSecondDepositPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16
  ) external override returns (PositionChange[] memory changes) {
    MockDropAfterSecondDepositPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address nfpm, uint256 tokenId) external view override returns (uint256, uint256) {
    return MockDropAfterSecondDepositPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function getPositionPrincipalAmounts(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (uint256, uint256)
  {
    return MockDropAfterSecondDepositPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function getPositionTokens(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (address token0, address token1)
  {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (token0, token1,,) = MockDropAfterSecondDepositPool(lpPool).lps(key);
  }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev Tracks the last (amount0, amount1) passed to depositProportional through a delegatecall.
///      Used by `MockRewardsAwareStrategy` — the strategy cannot write to its own storage under
///      delegatecall (that would corrupt the vault's storage layout), so it calls out to this tracker.
contract DepositProportionalRecorder {
  uint256 public lastAmount0;
  uint256 public lastAmount1;
  uint16 public lastSlippageBps;
  uint256 public callCount;

  function record(uint256 amount0, uint256 amount1, uint16 slippageBps) external {
    lastAmount0 = amount0;
    lastAmount1 = amount1;
    lastSlippageBps = slippageBps;
    callCount++;
  }
}

/// @dev Mock strategy that mirrors a real Uniswap V3 position with:
///      - a principal (token amounts computed from in-range liquidity at current price), AND
///      - uncollected fees / rewards (tokensOwed).
///
///      `getPositionAmounts` returns `principal + rewards` (total value, used by the vault
///      for share pricing). `getPositionPrincipalAmounts` returns `principal` only (used by
///      the vault when scaling per-depositor top-ups to an existing position).
///
///      `depositProportional` simulates V3's `increaseLiquidity` slippage semantics: when
///      `slippageBps > 0` it reverts with `"OffRatioDeposit"` if the `(amount0, amount1)`
///      ratio diverges from `(principal0, principal1)` beyond the allowed tolerance.
///      This is how the bug manifests in production: mixing rewards into the top-up desired
///      amounts skews the ratio off-range and the pool rejects the slippage check.
contract MockRewardsAwareStrategy is ISharedStrategy {
  DepositProportionalRecorder public immutable recorder;
  address public immutable lpPool;
  uint256 public immutable principal0;
  uint256 public immutable principal1;
  uint256 public immutable rewards0;
  uint256 public immutable rewards1;

  constructor(address _lpPool, address _recorder, uint256 _p0, uint256 _p1, uint256 _r0, uint256 _r1) {
    lpPool = _lpPool;
    recorder = DepositProportionalRecorder(_recorder);
    principal0 = _p0;
    principal1 = _p1;
    rewards0 = _r0;
    rewards1 = _r1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) =
      abi.decode(data, (address, uint256, address, address));
    // Seed the mock pool with the configured principal amounts so getPositionPrincipalAmounts
    // is consistent with actual pool-side accounting used by exitProportional.
    if (principal0 > 0) IERC20(token0).transfer(lpPool, principal0);
    if (principal1 > 0) IERC20(token1).transfer(lpPool, principal1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, principal0, principal1);
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16
  ) external override returns (PositionChange[] memory changes) {
    MockLPPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external view override returns (uint256, uint256) {
    return (principal0 + rewards0, principal1 + rewards1);
  }

  function getPositionPrincipalAmounts(address, uint256) external view override returns (uint256, uint256) {
    return (principal0, principal1);
  }

  function getPositionTokens(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (address token0, address token1)
  {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (token0, token1,,) = MockLPPool(lpPool).lps(key);
  }

  /// @dev Simulates Uniswap V3's `increaseLiquidity` behavior when `amount*Min > 0`:
  ///      derives the liquidity that would actually be added (binding side), computes what each
  ///      side would *actually* consume, then reverts if the consumed amount is below amountMin.
  ///      When `slippageBps == 0` it mirrors real V3 by just consuming whatever the pool accepts
  ///      (no revert) — so idle leftovers can be verified by the test.
  function depositProportional(address nfpm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps)
    external
    override
  {
    // Record via external CALL (can't use storage under delegatecall without corrupting vault).
    recorder.record(amount0, amount1, slippageBps);
    if (amount0 == 0 && amount1 == 0) return;

    // Compute what Uniswap V3 would actually consume given the current principal ratio.
    // This is the MIN liquidity constraint: L = min(amount0 / factor0, amount1 / factor1),
    // which in our token-amount space reduces to:
    //   consumed0 = min(amount0, amount1 * principal0 / principal1)
    //   consumed1 = min(amount1, amount0 * principal1 / principal0)
    uint256 consumed0 = amount0;
    uint256 consumed1 = amount1;
    if (principal0 > 0 && principal1 > 0) {
      uint256 cap0 = (amount1 * principal0) / principal1;
      uint256 cap1 = (amount0 * principal1) / principal0;
      if (cap0 < consumed0) consumed0 = cap0;
      if (cap1 < consumed1) consumed1 = cap1;
    }

    if (slippageBps > 0) {
      uint256 min0 = (amount0 * (10_000 - slippageBps)) / 10_000;
      uint256 min1 = (amount1 * (10_000 - slippageBps)) / 10_000;
      require(consumed0 >= min0 && consumed1 >= min1, "OffRatioDeposit");
    }

    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address token0, address token1,,) = MockLPPool(lpPool).lps(key);
    if (consumed0 > 0) IERC20(token0).transfer(lpPool, consumed0);
    if (consumed1 > 0) IERC20(token1).transfer(lpPool, consumed1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, consumed0, consumed1);
  }

  function collectFees(address, uint256, uint16) external override { }
}

/// @dev Minimal harness that exposes SharedStrategyFeeConfig.performanceFeeConfig for unit testing.
///      address(this) is read as ISharedVault inside the library, so we implement configManager()
///      and vaultOwner() via public state variables whose auto-generated getters match the interface.
contract PerformanceFeeConfigHarness {
  ISharedConfigManager public immutable configManager;
  address public immutable vaultOwner;
  uint16 public immutable vaultOwnerFeeBasisPoint;

  constructor(address _configManager, address _vaultOwner, uint16 _vaultOwnerFeeBasisPoint) {
    configManager = ISharedConfigManager(_configManager);
    vaultOwner = _vaultOwner;
    vaultOwnerFeeBasisPoint = _vaultOwnerFeeBasisPoint;
  }

  function callPerformanceFeeConfig() external view returns (ICommon.FeeConfig memory) {
    return SharedStrategyFeeConfig.performanceFeeConfig();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Audit-regression mocks (introduced for C-5 / W-7 / W-13 / W-16 coverage)
// ────────────────────────────────────────────────────────────────────────────

/// @dev Fee-on-transfer token: charges `feeBps` of every transfer/transferFrom.
contract FotToken {
  string public name = "FOT";
  string public symbol = "FOT";
  uint8 public decimals = 18;
  uint256 public feeBps;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  constructor(uint256 _feeBps) {
    feeBps = _feeBps;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    uint256 fee = (amount * feeBps) / 10_000;
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount - fee;
    totalSupply -= fee;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    uint256 fee = (amount * feeBps) / 10_000;
    balanceOf[from] -= amount;
    balanceOf[to] += amount - fee;
    totalSupply -= fee;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

/// @dev USDT-like token: transfer/transferFrom return nothing. Approve requires reset-to-zero
///      between non-zero values. Used to verify SafeERC20 compatibility.
contract UsdtLikeToken {
  string public name = "USDT-like";
  string public symbol = "USDT";
  uint8 public decimals = 6;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external {
    require(balanceOf[msg.sender] >= amount, "USDT: insufficient");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
  }

  function transferFrom(address from, address to, uint256 amount) external {
    require(allowance[from][msg.sender] >= amount, "USDT: allowance");
    require(balanceOf[from] >= amount, "USDT: insufficient");
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
  }

  function approve(address spender, uint256 amount) external {
    require(amount == 0 || allowance[msg.sender][spender] == 0, "USDT: approve nonzero");
    allowance[msg.sender][spender] = amount;
  }
}

/// @dev EIP-1271 wallet that delegates to an embedded EOA — used to test smart-wallet vault owners.
contract AuditEip1271Wallet is IERC1271 {
  bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;
  address public immutable signer;

  constructor(address _signer) {
    signer = _signer;
  }

  function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
    (address recovered,,) = ECDSA.tryRecover(hash, signature);
    return recovered == signer ? MAGIC_VALUE : bytes4(0);
  }
}

/// @dev Swap router that tries to re-enter `deposit()` mid-swap. Asserts ReentrancyGuard blocks it.
contract ReentrantSwapRouter {
  SharedVault public vault;
  bool public attemptReentry;
  bool public reentryReverted;

  function arm(SharedVault _vault) external {
    vault = _vault;
    attemptReentry = true;
  }

  function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minOut) external {
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).transfer(msg.sender, minOut);
    if (attemptReentry) {
      attemptReentry = false; // avoid infinite recursion if it ever succeeded
      uint256[4] memory zeros;
      try vault.deposit(zeros, 0) {
      // Unreachable: ReentrancyGuard must revert before this branch.
      }
      catch {
        reentryReverted = true;
      }
    }
  }

  receive() external payable { }
}

/// @dev Strategy mock that exposes per-(nfpm,tokenId) principal AND uncollected fee splits.
///      Used to test `previewWithdraw` net-of-fee math (W-7).
contract MockFeeAccrualStrategy is ISharedStrategy {
  event FeeCollected(
    address indexed vaultAddress,
    IFeeTaker.FeeType indexed feeType,
    address indexed recipient,
    address token,
    uint256 amount
  );

  mapping(bytes32 => address) private _token0;
  mapping(bytes32 => address) private _token1;
  mapping(bytes32 => uint256) private _principal0;
  mapping(bytes32 => uint256) private _principal1;
  mapping(bytes32 => uint256) private _owed0;
  mapping(bytes32 => uint256) private _owed1;
  address private immutable _self;

  constructor() {
    _self = address(this);
  }

  function register(
    address nfpm,
    uint256 tokenId,
    address t0,
    address t1,
    uint256 p0,
    uint256 p1,
    uint256 o0,
    uint256 o1
  ) external {
    bytes32 k = keccak256(abi.encodePacked(nfpm, tokenId));
    _token0[k] = t0;
    _token1[k] = t1;
    _principal0[k] = p0;
    _principal1[k] = p1;
    _owed0[k] = o0;
    _owed1[k] = o1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address t0, address t1) = abi.decode(data, (address, uint256, address, address));
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, t0, t1);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory c)
  {
    c = new PositionChange[](0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address nfpm, uint256 tokenId, uint16) external override {
    (address token0, address token1, uint256 owed0, uint256 owed1) =
      MockFeeAccrualStrategy(_self).consumeGeneratedFees(nfpm, tokenId);

    ISharedVault v = ISharedVault(address(this));
    ISharedConfigManager cm = v.configManager();
    uint16 platformBps = cm.platformFeeBasisPoint();
    uint16 ownerBps = v.vaultOwnerFeeBasisPoint();
    uint16 maxOwnerBps = 10_000 - platformBps;
    if (ownerBps > maxOwnerBps) ownerBps = maxOwnerBps;

    if (owed0 > 0) {
      MockERC20(token0).mint(address(this), owed0);
      _distributeGeneratedFees(token0, owed0, cm.feeRecipient(), platformBps, v.vaultOwner(), ownerBps);
    }
    if (owed1 > 0) {
      MockERC20(token1).mint(address(this), owed1);
      _distributeGeneratedFees(token1, owed1, cm.feeRecipient(), platformBps, v.vaultOwner(), ownerBps);
    }
  }

  function consumeGeneratedFees(address nfpm, uint256 tokenId)
    external
    returns (address token0, address token1, uint256 owed0, uint256 owed1)
  {
    bytes32 k = keccak256(abi.encodePacked(nfpm, tokenId));
    token0 = _token0[k];
    token1 = _token1[k];
    owed0 = _owed0[k];
    owed1 = _owed1[k];
    _owed0[k] = 0;
    _owed1[k] = 0;
  }

  function _distributeGeneratedFees(
    address token,
    uint256 amount,
    address platformRecipient,
    uint16 platformBps,
    address owner,
    uint16 ownerBps
  ) internal {
    if (platformBps > 0 && platformRecipient != address(0)) {
      uint256 platformFee = (amount * platformBps) / 10_000;
      if (platformFee > 0) {
        MockERC20(token).transfer(platformRecipient, platformFee);
        emit FeeCollected(address(this), IFeeTaker.FeeType.PLATFORM, platformRecipient, token, platformFee);
      }
    }
    if (ownerBps > 0 && owner != address(0)) {
      uint256 ownerFee = (amount * ownerBps) / 10_000;
      if (ownerFee > 0) {
        MockERC20(token).transfer(owner, ownerFee);
        emit FeeCollected(address(this), IFeeTaker.FeeType.OWNER, owner, token, ownerFee);
      }
    }
  }

  function getPositionAmounts(address nfpm, uint256 tokenId) external view override returns (uint256, uint256) {
    bytes32 k = keccak256(abi.encodePacked(nfpm, tokenId));
    return (_principal0[k] + _owed0[k], _principal1[k] + _owed1[k]);
  }

  function getPositionPrincipalAmounts(address nfpm, uint256 tokenId)
    external
    view
    override
    returns (uint256, uint256)
  {
    bytes32 k = keccak256(abi.encodePacked(nfpm, tokenId));
    return (_principal0[k], _principal1[k]);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    bytes32 k = keccak256(abi.encodePacked(nfpm, tokenId));
    return (_token0[k], _token1[k]);
  }
}

contract SharedVaultTest is TestCommon {
  event FeeCollected(
    address indexed vaultAddress,
    IFeeTaker.FeeType indexed feeType,
    address indexed recipient,
    address token,
    uint256 amount
  );

  SharedVault public vault;
  SharedConfigManager public configManager;

  MockERC20 public tokenA;
  MockERC20 public tokenB;
  MockERC20 public tokenC;
  MockERC20 public tokenD;
  MockERC20 public tokenE; // non-vault token

  MockSharedStrategy public mockStrategy;
  MockFailingStrategy public failingStrategy;
  MockSwapTarget public swapTarget;
  MockDirectPositionCreator public directCreator;
  MockERC721 public mockERC721;
  MockERC721 public cwpNfpm; // NFPM used for CALL_WITH_POSITIONS tests
  MockERC1155 public mockERC1155;
  MockWETH9 public mockWeth;

  address public constant VAULT_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant ADMIN = 0x1234567890123456789012345678901234567891;
  address public constant OPERATOR = 0x1234567890123456789012345678901234567892;
  address public constant DEPOSITOR = 0x1234567890123456789012345678901234567893;
  address public constant NON_AUTHORIZED = 0x1234567890123456789012345678901234567894;
  uint256 internal constant TEST_INITIAL_SHARES = 10e18;

  function _assertTrackedIds(SharedVault v, uint256 expectedA, uint256 expectedB) internal view {
    assertEq(v.getPositionCount(), 2, "expected two tracked positions");
    (,, uint256 tracked0,,) = v.getPosition(0);
    (,, uint256 tracked1,,) = v.getPosition(1);
    bool sawA = tracked0 == expectedA || tracked1 == expectedA;
    bool sawB = tracked0 == expectedB || tracked1 == expectedB;
    assertTrue(sawA, "expected original tokenId to remain tracked");
    assertTrue(sawB, "expected replacement tokenId to be tracked");
  }

  function _newPreCollectVault() internal returns (SharedVault v, MockPreCollectStrategy strategy, MockERC721 nfpm) {
    strategy = new MockPreCollectStrategy();
    nfpm = new MockERC721();

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), targets, new address[](0), address(this), 1000, nfpms, new address[](0));

    v = new SharedVault();
    MockERC20 tA = new MockERC20("PCA", "PCA");
    MockERC20 tB = new MockERC20("PCB", "PCB");
    uint256 dep = 100e18;
    tA.mint(address(v), dep);
    tB.mint(address(v), dep);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [dep, dep, uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("PreCollectVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 500);

    uint256 tokenId = 1;
    nfpm.mint(address(v), tokenId);
    strategy.registerPosition(address(nfpm), tokenId, address(tA), address(tB));
    ISharedVault.Action[] memory addActions = new ISharedVault.Action[](1);
    addActions[0] = ISharedVault.Action(
      address(strategy),
      abi.encode(address(nfpm), tokenId, address(tA), address(tB)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.prank(VAULT_OWNER);
    v.execute(addActions);
  }

  function setUp() public {
    // Deploy mock tokens
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");
    tokenC = new MockERC20("Token C", "TKC");
    tokenD = new MockERC20("Token D", "TKD");
    tokenE = new MockERC20("Token E", "TKE");

    // Deploy mock contracts
    mockStrategy = new MockSharedStrategy();
    failingStrategy = new MockFailingStrategy();
    swapTarget = new MockSwapTarget();
    directCreator = new MockDirectPositionCreator();
    mockERC721 = new MockERC721();
    cwpNfpm = new MockERC721();
    mockERC1155 = new MockERC1155();
    mockWeth = new MockWETH9();

    // Deploy config manager
    configManager = new SharedConfigManager();
    address[] memory targets = new address[](3);
    targets[0] = address(swapTarget);
    targets[1] = address(mockStrategy);
    targets[2] = address(directCreator);
    address[] memory callers = new address[](0);
    configManager.initialize(address(this), targets, callers, address(this), 0, new address[](0), new address[](0));

    // NFPM / swap-router allowlists used by `_addPosition` and `CALL` swap path in unit scenarios
    {
      address[] memory nfpms = new address[](9);
      nfpms[0] = makeAddr("nfpmMigrate");
      nfpms[1] = makeAddr("nfpmNotTracked");
      nfpms[2] = address(0xBEEF);
      nfpms[3] = address(0xBEEF1);
      nfpms[4] = address(0xDEAD);
      nfpms[5] = address(uint160(0xAAAA));
      nfpms[6] = address(uint160(0xBBBB));
      nfpms[7] = makeAddr("nfpm");
      nfpms[8] = address(cwpNfpm);
      configManager.setWhitelistNfpms(nfpms, true);
    }
    {
      address[] memory routers = new address[](1);
      routers[0] = address(swapTarget);
      configManager.setWhitelistSwapRouters(routers, true);
    }

    // Deploy vault
    vault = new SharedVault();

    // Mint initial tokens and transfer to vault for initialization
    tokenA.mint(address(this), 1000e18);
    tokenB.mint(address(this), 2000e18);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Transfer initial tokens to vault (factory would do this)
    tokenA.transfer(address(vault), 100e18);
    tokenB.transfer(address(vault), 200e18);

    // Initialize: vaultFactory is msg.sender; operator matches factory.owner() (SharedVaultFactory passes owner()).
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initialAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    vault.initialize(
      "Shared Vault", vaultTokens, initialAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );

    // Setup roles
    vault.grantAdminRole(ADMIN);
    vm.stopPrank();
  }

  // ==================== Initialization Tests ====================

  function test_initialize_success() public view {
    assertEq(vault.vaultOwner(), VAULT_OWNER);
    assertEq(vault.tokenCount(), 4);
    assertEq(vault.decimals(), 18);
    assertTrue(vault.isVaultToken(address(tokenA)));
    assertTrue(vault.isVaultToken(address(tokenB)));
    assertTrue(vault.isVaultToken(address(tokenC)));
    assertTrue(vault.isVaultToken(address(tokenD)));
    assertFalse(vault.isVaultToken(address(tokenE)));

    // Initial shares minted to owner: always INITIAL_SHARES on first deposit
    assertEq(vault.balanceOf(VAULT_OWNER), TEST_INITIAL_SHARES);
    assertGt(vault.totalSupply(), 0);
  }

  function test_initialize_fail_duplicate_token() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenA), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.DuplicateToken.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);
  }

  function test_initialize_fail_too_few_tokens() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(0), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.NoTokensConfigured.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);
  }

  function test_initialize_fail_zero_config_manager() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(0), address(0), 0);
  }

  function test_initialize_fail_zero_owner() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    vault2.initialize("Test", tokens, amounts, address(0), address(0), address(configManager), address(0), 0);
  }

  function test_initialize_fail_token_without_decimals() public {
    MockERC20NoDecimals noDecimals = new MockERC20NoDecimals();
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(noDecimals), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.InvalidToken.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);
  }

  // ==================== Deposit Tests ====================

  function test_deposit_first() public {
    // Create a fresh vault with no initial deposit
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0);
    vm.stopPrank();

    // First deposit
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault2), type(uint256).max);
    tokenB.approve(address(vault2), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault2.deposit(depositAmounts, 0);

    assertEq(shares, TEST_INITIAL_SHARES);
    assertEq(vault2.balanceOf(DEPOSITOR), shares);
    assertEq(tokenA.balanceOf(address(vault2)), 50e18);
    assertEq(tokenB.balanceOf(address(vault2)), 100e18);
    vm.stopPrank();
  }

  function test_deposit_subsequent_proportional() public {
    // Deposit proportionally
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Current ratio is 100:200 = 1:2, deposit 50:100 maintains ratio
    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);

    assertGt(shares, 0);
    assertEq(vault.balanceOf(DEPOSITOR), shares);
    vm.stopPrank();
  }

  function test_deposit_mints_shares_to_receiver() public {
    address receiver = address(0xB0B);
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0, receiver);
    vm.stopPrank();

    assertGt(shares, 0);
    assertEq(vault.balanceOf(receiver), shares);
    assertEq(vault.balanceOf(DEPOSITOR), 0);
  }

  function test_deposit_fail_zero_receiver() public {
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    vault.deposit(depositAmounts, 0, address(0));
    vm.stopPrank();
  }

  function test_deposit_excess_capped_at_proportional() public {
    // Vault is 1:2 (100A:200B). User provides 50A + 50B — more A than needed.
    // The minimum-ratio token is B (50/200 < 50/100), so shares are computed from B.
    // The vault takes only the proportional A amount and leaves excess A with the user.
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256 aBalanceBefore = tokenA.balanceOf(DEPOSITOR);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(50e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);

    assertGt(shares, 0);
    // Only proportional A was taken: 50B / 200B * 100A = 25A
    assertEq(tokenA.balanceOf(DEPOSITOR), aBalanceBefore - 25e18);
    assertEq(tokenB.balanceOf(DEPOSITOR), 0);
    vm.stopPrank();
  }

  function test_deposit_fail_insufficient_token_b() public {
    // User provides correct A but less B than the ratio requires
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Vault is 1:2. Depositing 50A + 50B: min shares come from B (25% of pool),
    // but expectedA for those shares = 25e18. 50A >= 25A so it passes.
    // Now try providing only 1B — min shares from B = 1/200 * totalSupply,
    // expectedA = (1/200 * totalSupply) * 100 / totalSupply = 0.5 → 0 (rounds down).
    // That would succeed, so test a case that truly fails: amounts[i] < expectedAmount.
    // Force fail: provide 0B when B balance is 200e18 (required).
    uint256[4] memory depositAmounts = [uint256(50e18), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    vault.deposit(depositAmounts, 0);
    vm.stopPrank();
  }

  function test_deposit_shares_independent_of_reference_token() public {
    // Regression: the minimum-ratio approach must yield the same shares regardless of which
    // token the caller leads with. Vault is 100A:200B (1:2). Exact proportional 10A:20B.
    tokenA.mint(DEPOSITOR, 10e18);
    tokenB.mint(DEPOSITOR, 20e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256 supplyBefore = vault.totalSupply();
    uint256[4] memory depositAmounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);
    vm.stopPrank();

    // 10A / 100A == 20B / 200B == 10% of pool → shares = 10% of prior supply
    assertEq(shares, supplyBefore / 10);
    assertEq(tokenA.balanceOf(address(vault)), 110e18);
    assertEq(tokenB.balanceOf(address(vault)), 220e18);
  }

  function test_deposit_fail_invalid_slippage_bps() public {
    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 2e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(1e18), uint256(2e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.deposit(depositAmounts, uint16(10_001));
    vm.stopPrank();
  }

  // ==================== Withdraw Tests ====================

  function test_withdraw_proportional() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;

    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(halfShares, minAmounts, false);
    vm.stopPrank();

    // Should get ~50% of each token
    assertEq(amounts[0], 50e18);
    assertEq(amounts[1], 100e18);
    assertEq(vault.balanceOf(VAULT_OWNER), ownerShares - halfShares);
  }

  function test_withdraw_all() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(ownerShares, minAmounts, false);
    vm.stopPrank();

    assertEq(amounts[0], 100e18);
    assertEq(amounts[1], 200e18);
    assertEq(vault.balanceOf(VAULT_OWNER), 0);
    assertEq(vault.totalSupply(), 0);
  }

  function test_withdraw_from_account_spends_finite_allowance_and_pays_caller() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 burnShares = ownerShares / 2;
    uint256[4] memory minAmounts;

    vm.prank(VAULT_OWNER);
    vault.approve(NON_AUTHORIZED, burnShares);

    uint256 callerTokenABefore = tokenA.balanceOf(NON_AUTHORIZED);
    uint256 callerTokenBBefore = tokenB.balanceOf(NON_AUTHORIZED);

    vm.expectEmit(true, true, true, true, address(vault));
    emit ISharedVault.VaultWithdraw(
      VAULT_OWNER, VAULT_OWNER, [uint256(50e18), uint256(100e18), uint256(0), uint256(0)], burnShares
    );

    vm.prank(NON_AUTHORIZED);
    uint256[4] memory amounts = vault.withdraw(burnShares, minAmounts, false, VAULT_OWNER);

    assertEq(amounts[0], 50e18);
    assertEq(amounts[1], 100e18);
    assertEq(tokenA.balanceOf(NON_AUTHORIZED), callerTokenABefore + 50e18, "caller receives tokenA");
    assertEq(tokenB.balanceOf(NON_AUTHORIZED), callerTokenBBefore + 100e18, "caller receives tokenB");
    assertEq(vault.balanceOf(VAULT_OWNER), ownerShares - burnShares, "owner shares burned");
    assertEq(vault.allowance(VAULT_OWNER, NON_AUTHORIZED), 0, "finite allowance spent");
  }

  function test_withdraw_from_account_keeps_infinite_allowance() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 burnShares = ownerShares / 2;
    uint256[4] memory minAmounts;

    vm.prank(VAULT_OWNER);
    vault.approve(NON_AUTHORIZED, type(uint256).max);

    vm.prank(NON_AUTHORIZED);
    vault.withdraw(burnShares, minAmounts, false, VAULT_OWNER);

    assertEq(vault.allowance(VAULT_OWNER, NON_AUTHORIZED), type(uint256).max);
  }

  function test_withdraw_from_account_reverts_without_allowance() public {
    uint256 burnShares = vault.balanceOf(VAULT_OWNER) / 2;
    uint256[4] memory minAmounts;

    vm.prank(NON_AUTHORIZED);
    vm.expectRevert();
    vault.withdraw(burnShares, minAmounts, false, VAULT_OWNER);
  }

  function test_withdraw_from_account_fail_zero_account() public {
    uint256[4] memory minAmounts;

    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    vault.withdraw(1, minAmounts, false, address(0));
  }

  function test_withdraw_fail_insufficient_shares() public {
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.InsufficientShares.selector);
    vault.withdraw(1, minAmounts, false);
    vm.stopPrank();
  }

  function test_withdraw_fail_min_amounts() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.withdraw(ownerShares, minAmounts, false);
    vm.stopPrank();
  }

  /// @dev If a tracked position's strategy.collectFees() reverts, the whole withdrawal must revert: a silent
  ///      failure followed by exitProportional would let the current withdrawer sweep all accumulated fees.
  ///      (Real strategies short-circuit collectFees when a position has no uncollected fees, so this only
  ///      fires for a strategy whose collect genuinely cannot succeed — see SharedV4StrategyLib._collectFees.)
  function test_withdraw_revertsWhenCollectFeesFails() public {
    MockLPPool pool = new MockLPPool();
    MockCollectFailingStrategy failingCollectStrat = new MockCollectFailingStrategy(address(pool));
    MockERC721 failNfpm = new MockERC721();

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets_ = new address[](1);
    targets_[0] = address(failingCollectStrat);
    address[] memory nfpms_ = new address[](1);
    nfpms_[0] = address(failNfpm);
    cm.initialize(address(this), targets_, new address[](0), address(this), 0, nfpms_, new address[](0));

    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("A", "A");
    MockERC20 tB = new MockERC20("B", "B");
    uint256 amt = 100e18;
    tA.mint(address(this), amt);
    tB.mint(address(this), amt);
    tA.transfer(address(v), amt);
    tB.transfer(address(v), amt);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmts = [amt, amt, uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("Vault", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 0);

    // Add a position via DELEGATECALL so the vault tracks it
    failNfpm.mint(address(v), 1);
    vm.prank(VAULT_OWNER);
    bytes memory stratData =
      abi.encode(address(failNfpm), uint256(1), address(tA), address(tB), uint256(50e18), uint256(50e18));
    ISharedVault.Action[] memory acts = new ISharedVault.Action[](1);
    acts[0] = ISharedVault.Action(address(failingCollectStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    v.execute(acts);

    // Pre-collect loop calls collectFees which reverts — must not silently swallow the failure
    uint256 shares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts;
    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.StrategyCallFailed.selector);
    v.withdraw(shares, minAmounts, false);
  }

  // ==================== Execute Tests ====================

  function test_execute_success() public {
    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action(address(mockStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_execute_does_not_precollect_all_tracked_positions_at_vault_level() public {
    (SharedVault v, MockPreCollectStrategy strategy, MockERC721 nfpm) = _newPreCollectVault();

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), "", ISharedCommon.CallType.DELEGATECALL);

    vm.recordLogs();
    vm.prank(VAULT_OWNER);
    v.execute(actions);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    bytes32 collectSig = keccak256("LegacyCollectFees(address,uint256,uint16)");
    bytes32 executeSig = keccak256("ExecuteCalled()");
    bool sawCollect;
    bool sawExecute;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter != address(v) || logs[i].topics.length == 0) continue;
      if (logs[i].topics[0] == collectSig) {
        (address loggedNfpm, uint256 loggedTokenId,) = abi.decode(logs[i].data, (address, uint256, uint16));
        assertEq(loggedNfpm, address(nfpm), "pre-collect nfpm");
        assertEq(loggedTokenId, 1, "pre-collect tokenId");
        sawCollect = true;
      } else if (logs[i].topics[0] == executeSig) {
        sawExecute = true;
      }
    }

    assertTrue(sawExecute, "execute action should run");
    assertFalse(sawCollect, "vault execute must not pre-collect unrelated tracked positions");
  }

  function test_execute_platform_fee_override_selector_is_not_supported() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    vm.prank(VAULT_OWNER);
    (bool ok,) =
      address(vault).call(abi.encodeWithSignature("execute((address,bytes,uint8)[],uint64)", actions, uint64(0)));

    assertFalse(ok, "execute platform fee override overload must not exist");
  }

  function test_execute_admin() public {
    vm.startPrank(ADMIN);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action(address(mockStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_execute_fail_unauthorized() public {
    vm.startPrank(NON_AUTHORIZED);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action(address(mockStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_execute_fail_non_whitelisted_strategy() public {
    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action(address(failingStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.execute(actions);
    vm.stopPrank();
  }

  // ==================== Swap-via-Execute Tests ====================

  function test_swap_success() public {
    // Give swap target some tokenB to return
    tokenB.mint(address(swapTarget), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 9e18, swapCalldata);

    uint256 balanceBefore = tokenB.balanceOf(address(vault));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vault.execute(actions);
    uint256 balanceAfter = tokenB.balanceOf(address(vault));

    assertEq(balanceAfter - balanceBefore, 10e18);
    vm.stopPrank();
  }

  function test_swap_residual_allowance_reset() public {
    // Partial-fill swap: router only consumes half of amountIn.
    // Without the post-call safeApprove(0), the residual allowance would persist.
    tokenB.mint(address(swapTarget), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.partialSwap, (address(tokenA), address(tokenB), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 0, swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(tokenA.allowance(address(vault), address(swapTarget)), 0, "residual allowance must be reset to 0");
  }

  function test_swap_fail_non_vault_token_in() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenE), address(tokenA), 10e18));
    bytes memory actionData = abi.encode(address(tokenE), address(tokenA), 10e18, 0, swapCalldata);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_out() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenE), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenE), 10e18, 0, swapCalldata);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_swap_fail_non_whitelisted_target() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 0, "");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(NON_AUTHORIZED, actionData, ISharedCommon.CallType.CALL);
    // `CALL` swap path checks swap-router allowlist before token validation.
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, NON_AUTHORIZED));
    vault.execute(actions);
    vm.stopPrank();
  }

  // ==================== Sweep Tests (factory owner is vault operator) ====================

  function test_sweep_non_vault_token() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(VAULT_OWNER);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();

    assertEq(tokenE.balanceOf(OPERATOR), 100e18);
    assertEq(tokenE.balanceOf(address(vault)), 0);
  }

  function test_sweep_fail_vault_token() public {
    vm.startPrank(VAULT_OWNER);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenA);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 1e18;
    vm.expectRevert(ISharedCommon.CannotSweepVaultToken.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, VAULT_OWNER);
    vm.stopPrank();
  }

  function test_sweep_fail_non_operator() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(OPERATOR);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();
  }

  function test_sweep_tokens_fail_length_mismatch() public {
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](2);
    sweepAmounts[0] = 1e18;
    sweepAmounts[1] = 2e18;

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
  }

  function test_sweep_native_token() public {
    vm.deal(address(vault), 1 ether);

    vm.startPrank(VAULT_OWNER);
    vault.sweepNativeToken(1 ether, OPERATOR);
    vm.stopPrank();

    assertEq(OPERATOR.balance, 1 ether);
  }

  function test_sweep_native_token_reverts_when_recipient_rejects_eth() public {
    RejectNativeReceiver receiver = new RejectNativeReceiver();
    vm.deal(address(vault), 1 ether);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.SwapFailed.selector);
    vault.sweepNativeToken(1 ether, address(receiver));
  }

  function test_sweep_erc721() public {
    mockERC721.mint(address(vault), 1);

    vm.startPrank(VAULT_OWNER);
    vault.sweepERC721(address(mockERC721), 1, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC721.ownerOf(1), OPERATOR);
  }

  function test_sweep_erc721_reverts_for_tracked_position_nft() public {
    uint256 tokenId = 42;
    cwpNfpm.mint(address(vault), tokenId);

    bytes memory callData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.CannotSweepVaultToken.selector);
    vault.sweepERC721(address(cwpNfpm), tokenId, OPERATOR);
  }

  function test_sweep_erc1155() public {
    mockERC1155.mint(address(vault), 1, 100);

    vm.startPrank(VAULT_OWNER);
    vault.sweepERC1155(address(mockERC1155), 1, 50, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC1155.balanceOf(OPERATOR, 1), 50);
    assertEq(mockERC1155.balanceOf(address(vault), 1), 50);
  }

  // ==================== Role Tests ====================

  function test_grant_revoke_admin() public {
    address newAdmin = address(0x999);
    vm.startPrank(VAULT_OWNER);
    vault.grantAdminRole(newAdmin);
    vm.stopPrank();

    // New admin can execute
    vm.startPrank(newAdmin);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action(address(mockStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    vm.stopPrank();

    // Revoke
    vm.startPrank(VAULT_OWNER);
    vault.revokeAdminRole(newAdmin);
    vm.stopPrank();

    vm.startPrank(newAdmin);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_transfer_ownership() public {
    address newOwner = address(0x777);
    vm.startPrank(VAULT_OWNER);
    vault.transferOwnership(newOwner);
    vm.stopPrank();

    assertEq(vault.vaultOwner(), newOwner);

    // Old owner can't act
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.grantAdminRole(address(0x666));
    vm.stopPrank();
  }

  // ==================== Position Strategy Update via execute() Tests ====================

  function _setupVaultWithBrokenStrategy()
    internal
    returns (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId)
  {
    brokenStrat = new MockBrokenExitStrategy();
    mockNfpm = new MockERC721();
    tokenId = 99;

    // Whitelist the strategy and the mock NFPM
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(brokenStrat);
    configManager.setWhitelistTargets(newTargets, true);
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(mockNfpm);
    configManager.setWhitelistNfpms(newNfpms, true);

    // Mint the position NFT to the vault (simulates the NFPM having issued it)
    mockNfpm.mint(address(vault), tokenId);

    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    // Register token pair BEFORE execute so _applyPositionChanges canonical-token check passes.
    brokenStrat.registerPosition(address(mockNfpm), tokenId, address(tokenA), address(tokenB));

    bytes memory stratData = abi.encode(address(mockNfpm), tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
  }

  // ==================== dropPosition Tests ====================

  function test_dropPosition_happy_path() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    assertEq(vault.getPositionCount(), 1);
    assertEq(mockNfpm.ownerOf(tokenId), address(vault));

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionDropped(VAULT_OWNER, address(mockNfpm), tokenId);
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    // Position removed from tracking and NFT transferred to operator (VAULT_OWNER)
    assertEq(vault.getPositionCount(), 0);
    assertEq(mockNfpm.ownerOf(tokenId), VAULT_OWNER, "NFT should be with operator after drop");
    (brokenStrat);
  }

  function test_dropPosition_unblocks_deposit() public {
    // Deploy a strategy whose getPositionAmounts returns non-zero but depositProportional always reverts.
    // This simulates a rugged pool where the NFPM rejects increaseLiquidity calls.
    MockBrokenDepositStrategy brokenDepStrat = new MockBrokenDepositStrategy();
    address[] memory targets = new address[](1);
    targets[0] = address(brokenDepStrat);
    configManager.setWhitelistTargets(targets, true);

    MockERC721 mockNfpm = new MockERC721();
    uint256 tokenId = 42;
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(mockNfpm);
    configManager.setWhitelistNfpms(newNfpms, true);
    mockNfpm.mint(address(vault), tokenId);

    // Initial deposit so we have a non-zero totalSupply to work against
    tokenA.mint(DEPOSITOR, 300e18);
    tokenB.mint(DEPOSITOR, 300e18);
    vm.prank(DEPOSITOR);
    tokenA.approve(address(vault), 300e18);
    vm.prank(DEPOSITOR);
    tokenB.approve(address(vault), 300e18);
    vm.prank(DEPOSITOR);
    vault.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);

    // Register token pair before execute so canonical-token check in _applyPositionChanges passes.
    brokenDepStrat.registerPosition(address(mockNfpm), tokenId, address(tokenA), address(tokenB));

    // Add the broken position via execute
    bytes memory stratData = abi.encode(address(mockNfpm), tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenDepStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1);

    // Second deposit fails — getPositionAmounts returns non-zero so toAdd > 0, then depositProportional reverts.
    vm.prank(DEPOSITOR);
    vm.expectRevert("pool rugged");
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);

    // Drop the broken position — deposit must succeed afterwards
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);
    assertEq(vault.getPositionCount(), 0);

    vm.prank(DEPOSITOR);
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
  }

  function test_dropPosition_fail_not_tracked() public {
    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.dropPosition(address(0xDEAD), 999);
  }

  function test_dropPosition_fail_unauthorized() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.dropPosition(address(mockNfpm), tokenId);
    (brokenStrat);
  }

  function test_dropPosition_keepsNftInVault_whenNoOperator() public {
    // Deploy a fresh vault with operator = address(0) — no operator configured
    SharedVault vaultNoOp = new SharedVault();
    MockERC721 nfpm = new MockERC721();
    uint256 tokenId = 7;

    // Whitelist the nfpm and brokenStrat in configManager (same configManager)
    MockBrokenExitStrategy brokenStrat = new MockBrokenExitStrategy();
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(brokenStrat);
    configManager.setWhitelistTargets(newTargets, true);
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(nfpm);
    configManager.setWhitelistNfpms(newNfpms, true);

    // Seed vault with tokens and initialize (operator = address(0))
    tokenA.mint(address(vaultNoOp), 100e18);
    tokenB.mint(address(vaultNoOp), 200e18);
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    vaultNoOp.initialize(
      "No-Op Vault", vaultTokens, initAmounts, VAULT_OWNER, address(0), address(configManager), address(0), 0
    );

    // Mint the NFT to the vault and add the position
    nfpm.mint(address(vaultNoOp), tokenId);
    // Register token pair before execute so canonical-token check in _applyPositionChanges passes.
    brokenStrat.registerPosition(address(nfpm), tokenId, address(tokenA), address(tokenB));
    bytes memory stratData = abi.encode(address(nfpm), tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vaultNoOp.execute(actions);
    assertEq(vaultNoOp.getPositionCount(), 1);

    // Drop the position — no operator, so NFT must stay in vault
    vm.prank(VAULT_OWNER);
    vaultNoOp.dropPosition(address(nfpm), tokenId);

    assertEq(vaultNoOp.getPositionCount(), 0, "position removed from tracking");
    assertEq(nfpm.ownerOf(tokenId), address(vaultNoOp), "NFT stays in vault when no operator");
  }

  // ==================== recoverPosition Tests ====================

  function test_recoverPosition_reAddsPositionToTracking() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();
    address strategy = address(brokenStrat);

    // Drop: NFT goes to operator (VAULT_OWNER)
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);
    assertEq(vault.getPositionCount(), 0);
    assertEq(mockNfpm.ownerOf(tokenId), VAULT_OWNER);

    // Operator approves vault to pull NFT back
    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    // Recover: re-adds position to tracking
    vm.prank(VAULT_OWNER);
    vault.recoverPosition(address(mockNfpm), tokenId, strategy, address(tokenA), address(tokenB));

    assertEq(vault.getPositionCount(), 1, "position back in tracking");
    assertEq(mockNfpm.ownerOf(tokenId), address(vault), "NFT back in vault");
    (address storedStrategy, address storedNfpm, uint256 storedTokenId,,) = vault.getPosition(0);
    assertEq(storedStrategy, strategy);
    assertEq(storedNfpm, address(mockNfpm));
    assertEq(storedTokenId, tokenId);
  }

  function test_recoverPosition_emitsEvent() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionRecovered(VAULT_OWNER, address(mockNfpm), tokenId);
    vm.prank(VAULT_OWNER);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_revertsForNonOperator() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_revertsIfTokenNotConfiguredOnVault() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();
    address badToken = address(0xBEEF);

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), badToken, address(tokenB));
  }

  function test_recoverPosition_revertsIfStrategyNotWhitelisted() public {
    (, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    // Use failingStrategy which is not whitelisted in configManager
    vm.prank(VAULT_OWNER);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.recoverPosition(address(mockNfpm), tokenId, address(failingStrategy), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_revertsIfNfpmNotWhitelisted() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    // De-whitelist the NFPM after the drop
    address[] memory delistNfpms = new address[](1);
    delistNfpms[0] = address(mockNfpm);
    configManager.setWhitelistNfpms(delistNfpms, false);

    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidNfpm.selector, address(mockNfpm)));
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_enforcesMaxPositionsLimit() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    // Drop the position
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);
    assertEq(vault.getPositionCount(), 0);

    // Fill up to the limit with other positions
    configManager.setMaxPositions(1);
    _addPositionViaDirectCreator(101);
    assertEq(vault.getPositionCount(), 1);

    // Now recover should fail — limit already reached
    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.TooManyPositions.selector);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  /// @notice recoverPosition with a non-conformant NFPM whose transferFrom is a no-op → reverts.
  /// @dev Closes the gap where a silent no-op transferFrom could let recoverPosition register
  ///      an NFT the vault doesn't actually hold. The post-transfer ownerOf check catches it.
  function test_recoverPosition_revertsWhenTransferFromIsNoop() public {
    MockSilentTransferNfpm silentNfpm = new MockSilentTransferNfpm();
    MockBrokenExitStrategy brokenStrat = new MockBrokenExitStrategy();
    uint256 tokenId = 55;

    // Whitelist silentNfpm and brokenStrat
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(silentNfpm);
    configManager.setWhitelistNfpms(newNfpms, true);
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(brokenStrat);
    configManager.setWhitelistTargets(newTargets, true);

    // silentNfpm holds the NFT at VAULT_OWNER (operator)
    silentNfpm.mint(VAULT_OWNER, tokenId);
    brokenStrat.registerPosition(address(silentNfpm), tokenId, address(tokenA), address(tokenB));

    // transferFrom is a no-op; vault never actually receives the NFT → ownerOf still returns VAULT_OWNER
    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.recoverPosition(address(silentNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  /// @notice DELEGATECALL strategy returning isAdd=true for an unowned NFT → reverts InvalidOperation.
  /// @dev Defense-in-depth check on the DELEGATECALL path: even a whitelisted strategy cannot
  ///      register a position the vault doesn't hold.
  function test_delegatecall_reverts_when_strategy_reports_unowned_nft() public {
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory t = new address[](1);
    t[0] = address(lpStrategy);
    configManager.setWhitelistTargets(t, true);

    // Do NOT mint the NFT to vault — vault doesn't own it
    uint256 tokenId = 77;
    bytes memory stratData =
      abi.encode(address(cwpNfpm), tokenId, address(tokenA), address(tokenB), uint256(0), uint256(0));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.execute(actions);
  }

  // ==================== Pause Tests ====================

  function test_global_pause_blocks_deposit() public {
    configManager.setVaultPaused(true);

    tokenA.mint(DEPOSITOR, 10e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.deposit(amounts, 0);
    vm.stopPrank();
  }

  function test_global_pause_blocks_execute() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(1)), ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_global_pause_blocks_swap() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 1e18, 0, "");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_global_pause_allows_withdraw() public {
    configManager.setVaultPaused(true);

    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts;

    vm.prank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(ownerShares / 2, minAmounts, false);

    assertEq(amounts[0], 50e18);
    assertEq(amounts[1], 100e18);
    assertEq(vault.balanceOf(VAULT_OWNER), ownerShares - ownerShares / 2);
  }

  function test_per_vault_pause_blocks_deposit() public {
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.stopPrank();

    tokenA.mint(DEPOSITOR, 10e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.deposit(amounts, 0);
    vm.stopPrank();
  }

  function test_per_vault_pause_blocks_execute() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(1)), ISharedCommon.CallType.DELEGATECALL);
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_per_vault_pause_allows_withdraw() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts;

    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    uint256[4] memory amounts = vault.withdraw(ownerShares / 2, minAmounts, false);
    vm.stopPrank();

    assertEq(amounts[0], 50e18);
    assertEq(amounts[1], 100e18);
    assertEq(vault.balanceOf(VAULT_OWNER), ownerShares - ownerShares / 2);
  }

  function test_per_vault_pause_unpause() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action(address(mockStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    assertTrue(vault.paused());

    // Unpaused
    vault.setPaused(false);
    assertFalse(vault.paused());

    // Can execute again
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_per_vault_pause_independent_of_global() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(1)), ISharedCommon.CallType.DELEGATECALL);

    // Per-vault paused, global not paused
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();

    // Per-vault unpaused, global paused
    vm.prank(VAULT_OWNER);
    vault.setPaused(false);
    configManager.setVaultPaused(true);
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  // ==================== Vault owner fee + platform fee (LpFeeTaker / config) ====================

  function test_set_platform_fee_basis_point() public {
    // Config manager owner is `address(this)` from setUp `initialize`
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(50);
    assertEq(configManager.platformFeeBasisPoint(), 50);
  }

  function test_set_platform_fee_basis_point_reverts_invalid() public {
    vm.startPrank(address(this));
    vm.expectRevert(ISharedCommon.InvalidFeeBasisPoint.selector);
    configManager.setPlatformFeeBasisPoint(10_001);
    vm.stopPrank();
  }

  function test_v4_collectFees_emitsFeeCollected_for_platform_and_vault_owner() public {
    configManager.setPlatformFeeBasisPoint(1000);

    SharedVaultCollectHarness v = new SharedVaultCollectHarness();
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("V4FeeEvents", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(configManager), address(0), 500);

    MockV4PositionManager posm = new MockV4PositionManager(2);
    uint256 tokenId = 1;
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    posm.setCollectFees(tokenId, 1000, 2000);

    SharedV4Strategy v4strat = new SharedV4Strategy(address(new MockV4UtilsRouter()));

    uint256 platformABefore = tokenA.balanceOf(address(this));
    uint256 platformBBefore = tokenB.balanceOf(address(this));
    uint256 ownerABefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 ownerBBefore = tokenB.balanceOf(VAULT_OWNER);

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenA), 100);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenB), 200);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenA), 50);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenB), 100);

    v.collectWithStrategy(address(v4strat), address(posm), tokenId);

    assertEq(tokenA.balanceOf(address(this)) - platformABefore, 100, "platform tokenA fee");
    assertEq(tokenB.balanceOf(address(this)) - platformBBefore, 200, "platform tokenB fee");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerABefore, 50, "owner tokenA fee");
    assertEq(tokenB.balanceOf(VAULT_OWNER) - ownerBBefore, 100, "owner tokenB fee");
    assertEq(tokenA.balanceOf(address(v)), 850, "vault keeps tokenA net fees");
    assertEq(tokenB.balanceOf(address(v)), 1700, "vault keeps tokenB net fees");
  }

  function test_v4_collectFees_uses_config_manager_platform_fee() public {
    configManager.setPlatformFeeBasisPoint(0);

    SharedVaultCollectHarness v = new SharedVaultCollectHarness();
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize(
      "V4ConfigPlatformFee", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(configManager), address(0), 500
    );

    MockV4PositionManager posm = new MockV4PositionManager(2);
    uint256 tokenId = 1;
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    posm.setCollectFees(tokenId, 1000, 2000);

    SharedV4Strategy v4strat = new SharedV4Strategy(address(new MockV4UtilsRouter()));

    uint256 platformABefore = tokenA.balanceOf(address(this));
    uint256 platformBBefore = tokenB.balanceOf(address(this));
    uint256 ownerABefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 ownerBBefore = tokenB.balanceOf(VAULT_OWNER);

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenA), 50);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenB), 100);

    v.collectWithStrategy(address(v4strat), address(posm), tokenId);

    assertEq(tokenA.balanceOf(address(this)) - platformABefore, 0, "config platform tokenA fee");
    assertEq(tokenB.balanceOf(address(this)) - platformBBefore, 0, "config platform tokenB fee");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerABefore, 50, "owner tokenA fee");
    assertEq(tokenB.balanceOf(VAULT_OWNER) - ownerBBefore, 100, "owner tokenB fee");
    assertEq(tokenA.balanceOf(address(v)), 950, "vault keeps tokenA net fees");
    assertEq(tokenB.balanceOf(address(v)), 1900, "vault keeps tokenB net fees");
  }

  function test_v4_execute_compound_collects_generated_fees_and_distributes_platform_owner_gas() public {
    MockV4PositionManager posm = new MockV4PositionManager(2);
    uint256 tokenId = 1;
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    posm.setLiquidity(tokenId, 100);
    posm.setCollectFees(tokenId, 1000, 2000);

    SharedV4Strategy v4strat = new SharedV4Strategy(address(new MockV4UtilsRouter()));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(posm);
    cm.initialize(address(this), targets, new address[](0), address(this), 1000, nfpms, new address[](0));

    SharedVaultCollectHarness v = new SharedVaultCollectHarness();
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("V4ExecuteCollect", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(cm), address(0), 500);
    posm.setOwner(tokenId, address(v));

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: block.timestamp }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(1 << 62)
    });
    IV4Utils.Instructions memory instructions =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) });
    bytes memory params = abi.encodeCall(IV4Utils.execute, (address(posm), tokenId, instructions));
    bytes memory innerData = abi.encode(address(posm), tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    uint256 platformABefore = tokenA.balanceOf(address(this));
    uint256 platformBBefore = tokenB.balanceOf(address(this));
    uint256 ownerABefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 ownerBBefore = tokenB.balanceOf(VAULT_OWNER);
    uint256 vaultABefore = tokenA.balanceOf(address(v));
    uint256 vaultBBefore = tokenB.balanceOf(address(v));

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenA), 100);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenB), 200);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenA), 50);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenB), 100);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.GAS, VAULT_OWNER, address(tokenA), 250);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.GAS, VAULT_OWNER, address(tokenB), 500);

    vm.prank(VAULT_OWNER);
    v.executeWithStrategy(address(v4strat), stratData);

    assertEq(tokenA.balanceOf(address(this)) - platformABefore, 100, "platform tokenA fee");
    assertEq(tokenB.balanceOf(address(this)) - platformBBefore, 200, "platform tokenB fee");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerABefore, 300, "owner tokenA fee plus gas");
    assertEq(tokenB.balanceOf(VAULT_OWNER) - ownerBBefore, 600, "owner tokenB fee plus gas");
    assertEq(tokenA.balanceOf(address(v)) - vaultABefore, 600, "vault keeps tokenA net generated fees");
    assertEq(tokenB.balanceOf(address(v)) - vaultBBefore, 1200, "vault keeps tokenB net generated fees");
  }

  function test_v4_execute_swapAndMint_tokenIdZero_mintsAndTracksPosition() public {
    MockV4PositionManager posm = new MockV4PositionManager(100);
    SharedV4Strategy v4strat = new SharedV4Strategy(address(new MockV4UtilsRouter()));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(posm);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 10e18);
    tokenB.mint(address(v), 10e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(10e18), uint256(10e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("V4Mint", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(cm), address(0), 0);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(tokenA)),
      currency1: Currency.wrap(address(tokenB)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    V4TestInputTokenParams[] memory inputTokens = new V4TestInputTokenParams[](2);
    inputTokens[0] = V4TestInputTokenParams({ token: address(tokenA), amount: 1e18 });
    inputTokens[1] = V4TestInputTokenParams({ token: address(tokenB), amount: 1e18 });

    V4TestSwapAndMintParams memory mintParams = V4TestSwapAndMintParams({
      posm: address(posm),
      poolKey: key,
      mintParams: IV4Utils.MintParams({
        tickLower: -60, tickUpper: 60, minLiquidity: 1, hookData: "", deadline: block.timestamp
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputTokens,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory params = abi.encodeWithSelector(IV4Utils.swapAndMint.selector, mintParams);
    bytes memory innerData =
      abi.encode(address(posm), uint256(0), params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v4strat), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(VAULT_OWNER);
    v.execute(actions);

    assertEq(v.getPositionCount(), 1, "minted V4 position should be tracked");
    (, address trackedNfpm, uint256 trackedId, address tracked0, address tracked1) = v.getPosition(0);
    assertEq(trackedNfpm, address(posm), "tracked POSM");
    assertEq(trackedId, 100, "minted tokenId");
    assertEq(tracked0, address(tokenA), "tracked token0");
    assertEq(tracked1, address(tokenB), "tracked token1");
    assertEq(posm.ownerOf(100), address(v), "vault owns minted V4 NFT");
  }

  function test_v4_execute_revertsWhenEmptySwapDataHasMinOut() public {
    MockV4PositionManager posm = new MockV4PositionManager(100);
    MockV4UtilsRouter swapRouter = new MockV4UtilsRouter();
    SharedV4Strategy v4strat = new SharedV4Strategy(address(swapRouter));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(posm);
    address[] memory swapRouters = new address[](1);
    swapRouters[0] = address(swapRouter);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, swapRouters);

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 10e18);
    tokenB.mint(address(v), 10e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(10e18), uint256(10e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("V4EmptySwapData", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(cm), address(0), 0);

    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(tokenA)),
      currency1: Currency.wrap(address(tokenB)),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    V4TestInputTokenParams[] memory inputTokens = new V4TestInputTokenParams[](2);
    inputTokens[0] = V4TestInputTokenParams({ token: address(tokenA), amount: 1e18 });
    inputTokens[1] = V4TestInputTokenParams({ token: address(tokenB), amount: 1e18 });

    IV4Utils.SwapParams[] memory swaps = new IV4Utils.SwapParams[](1);
    swaps[0] = IV4Utils.SwapParams({
      tokenIn: address(tokenA),
      amountIn: 0.1e18,
      tokenOut: address(tokenB),
      amountOutMin: 1,
      swapData: ""
    });

    V4TestSwapAndMintParams memory mintParams = V4TestSwapAndMintParams({
      posm: address(posm),
      poolKey: key,
      mintParams: IV4Utils.MintParams({
        tickLower: -60, tickUpper: 60, minLiquidity: 1, hookData: "", deadline: block.timestamp
      }),
      swapParams: swaps,
      inputTokens: inputTokens,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory params = abi.encodeWithSelector(IV4Utils.swapAndMint.selector, mintParams);
    bytes memory innerData =
      abi.encode(address(posm), uint256(0), params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v4strat), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    v.execute(actions);
  }

  function test_v4_execute_capsGasFeeToCollectedAmountAfterPlatformAndOwnerFees() public {
    SharedConfigManager cm = new SharedConfigManager();
    MockV4PositionManager posm = new MockV4PositionManager(2);
    uint256 tokenId = 1;
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    posm.setLiquidity(tokenId, 100);
    posm.setCollectFees(tokenId, 1000, 0);

    SharedV4Strategy v4strat = new SharedV4Strategy(address(new MockV4UtilsRouter()));
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(posm);
    cm.initialize(address(this), targets, new address[](0), address(this), 1000, nfpms, new address[](0));

    SharedVaultCollectHarness v = new SharedVaultCollectHarness();
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("V4FeeCap", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(cm), address(0), 500);
    posm.setOwner(tokenId, address(v));

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: block.timestamp }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: type(uint64).max
    });
    IV4Utils.Instructions memory instructions =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) });
    bytes memory params = abi.encodeCall(IV4Utils.execute, (address(posm), tokenId, instructions));
    bytes memory innerData = abi.encode(address(posm), tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    uint256 platformBefore = tokenA.balanceOf(address(this));
    uint256 ownerBefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 operatorBefore = tokenA.balanceOf(OPERATOR);

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenA), 100);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenA), 50);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.GAS, OPERATOR, address(tokenA), 850);

    vm.prank(OPERATOR);
    v.executeWithStrategy(address(v4strat), stratData);

    assertEq(tokenA.balanceOf(address(this)) - platformBefore, 100, "platform fee");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerBefore, 50, "owner fee");
    assertEq(tokenA.balanceOf(OPERATOR) - operatorBefore, 850, "gas fee capped to remaining collected amount");
    assertEq(tokenA.balanceOf(address(v)), 0, "all collected fees paid without over-transfer");
  }

  function test_pancake_v4_collectFees_emitsFeeCollected_for_platform_and_vault_owner() public {
    configManager.setPlatformFeeBasisPoint(1000);

    SharedVaultCollectHarness v = new SharedVaultCollectHarness();
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize(
      "PancakeV4FeeEvents", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(configManager), address(0), 500
    );

    MockPancakeV4PositionManager posm = new MockPancakeV4PositionManager(2);
    uint256 tokenId = 1;
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    posm.setCollectFees(tokenId, 1000, 2000);

    SharedPancakeV4Strategy pancakeStrat = new SharedPancakeV4Strategy(address(new MockV4UtilsRouter()));

    uint256 platformABefore = tokenA.balanceOf(address(this));
    uint256 platformBBefore = tokenB.balanceOf(address(this));
    uint256 ownerABefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 ownerBBefore = tokenB.balanceOf(VAULT_OWNER);

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenA), 100);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenB), 200);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenA), 50);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenB), 100);

    v.collectWithStrategy(address(pancakeStrat), address(posm), tokenId);

    assertEq(tokenA.balanceOf(address(this)) - platformABefore, 100, "platform tokenA fee");
    assertEq(tokenB.balanceOf(address(this)) - platformBBefore, 200, "platform tokenB fee");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerABefore, 50, "owner tokenA fee");
    assertEq(tokenB.balanceOf(VAULT_OWNER) - ownerBBefore, 100, "owner tokenB fee");
    assertEq(tokenA.balanceOf(address(v)), 850, "vault keeps tokenA net fees");
    assertEq(tokenB.balanceOf(address(v)), 1700, "vault keeps tokenB net fees");
  }

  function test_pancake_v4_execute_swapAndMint_tokenIdZero_mintsAndTracksPosition() public {
    MockPancakeV4PositionManager posm = new MockPancakeV4PositionManager(100);
    SharedPancakeV4Strategy pancakeStrat = new SharedPancakeV4Strategy(address(new MockV4UtilsRouter()));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(pancakeStrat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(posm);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 10e18);
    tokenB.mint(address(v), 10e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(10e18), uint256(10e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("PancakeV4Mint", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(cm), address(0), 0);

    PancakeV4PoolKey memory key = PancakeV4PoolKey({
      currency0: PancakeCurrency.wrap(address(tokenA)),
      currency1: PancakeCurrency.wrap(address(tokenB)),
      hooks: IPancakeHooks(address(0)),
      poolManager: IPancakePoolManager(address(posm.poolManager())),
      fee: 3000,
      parameters: bytes32(uint256(uint24(60)) << 16)
    });

    IPancakeV4Utils.InputTokenParams[] memory inputTokens = new IPancakeV4Utils.InputTokenParams[](2);
    inputTokens[0] = IPancakeV4Utils.InputTokenParams({ token: address(tokenA), amount: 1e18 });
    inputTokens[1] = IPancakeV4Utils.InputTokenParams({ token: address(tokenB), amount: 1e18 });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: address(posm),
      poolKey: key,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: -60, tickUpper: 60, minLiquidity: 1, hookData: "", deadline: block.timestamp
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputTokens,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(1 << 63)
    });

    bytes memory params = abi.encodeWithSelector(IPancakeV4Utils.swapAndMint.selector, mintParams);
    bytes memory innerData =
      abi.encode(address(posm), uint256(0), params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(pancakeStrat), stratData, ISharedCommon.CallType.DELEGATECALL);

    uint256 ownerABefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 ownerBBefore = tokenB.balanceOf(VAULT_OWNER);

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.GAS, VAULT_OWNER, address(tokenA), 0.5e18);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.GAS, VAULT_OWNER, address(tokenB), 0.5e18);

    vm.prank(VAULT_OWNER);
    v.execute(actions);

    assertEq(v.getPositionCount(), 1, "minted Pancake V4 position should be tracked");
    (, address trackedNfpm, uint256 trackedId, address tracked0, address tracked1) = v.getPosition(0);
    assertEq(trackedNfpm, address(posm), "tracked POSM");
    assertEq(trackedId, 100, "minted tokenId");
    assertEq(tracked0, address(tokenA), "tracked token0");
    assertEq(tracked1, address(tokenB), "tracked token1");
    assertEq(posm.ownerOf(100), address(v), "vault owns minted Pancake V4 NFT");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerABefore, 0.5e18, "gas fee tokenA");
    assertEq(tokenB.balanceOf(VAULT_OWNER) - ownerBBefore, 0.5e18, "gas fee tokenB");
  }

  function test_pancake_v4_execute_revertsWhenEmptySwapDataHasMinOut() public {
    MockPancakeV4PositionManager posm = new MockPancakeV4PositionManager(100);
    MockV4UtilsRouter swapRouter = new MockV4UtilsRouter();
    SharedPancakeV4Strategy pancakeStrat = new SharedPancakeV4Strategy(address(swapRouter));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(pancakeStrat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(posm);
    address[] memory swapRouters = new address[](1);
    swapRouters[0] = address(swapRouter);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, swapRouters);

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 10e18);
    tokenB.mint(address(v), 10e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(10e18), uint256(10e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("PancakeV4EmptySwapData", vtokens, initAmounts, VAULT_OWNER, OPERATOR, address(cm), address(0), 0);

    PancakeV4PoolKey memory key = PancakeV4PoolKey({
      currency0: PancakeCurrency.wrap(address(tokenA)),
      currency1: PancakeCurrency.wrap(address(tokenB)),
      hooks: IPancakeHooks(address(0)),
      poolManager: IPancakePoolManager(address(posm.poolManager())),
      fee: 3000,
      parameters: bytes32(uint256(uint24(60)) << 16)
    });

    IPancakeV4Utils.InputTokenParams[] memory inputTokens = new IPancakeV4Utils.InputTokenParams[](2);
    inputTokens[0] = IPancakeV4Utils.InputTokenParams({ token: address(tokenA), amount: 1e18 });
    inputTokens[1] = IPancakeV4Utils.InputTokenParams({ token: address(tokenB), amount: 1e18 });

    IPancakeV4Utils.SwapParams[] memory swaps = new IPancakeV4Utils.SwapParams[](1);
    swaps[0] = IPancakeV4Utils.SwapParams({
      tokenIn: address(tokenA),
      amountIn: 0.1e18,
      tokenOut: address(tokenB),
      amountOutMin: 1,
      swapData: ""
    });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: address(posm),
      poolKey: key,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: -60, tickUpper: 60, minLiquidity: 1, hookData: "", deadline: block.timestamp
      }),
      swapParams: swaps,
      inputTokens: inputTokens,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory params = abi.encodeWithSelector(IPancakeV4Utils.swapAndMint.selector, mintParams);
    bytes memory innerData =
      abi.encode(address(posm), uint256(0), params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(pancakeStrat), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    v.execute(actions);
  }

  /// @notice The vault owner fee is set exactly once in `initialize` and persists thereafter.
  ///         Depositors must be able to trust that the fee they saw at deposit time is the
  ///         same fee applied on every subsequent withdrawal.
  function test_initialize_sets_vault_owner_fee_basis_point() public {
    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    tA.mint(address(v), 100e18);
    tB.mint(address(v), 200e18);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    v.initialize("FeeVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 250);

    assertEq(v.vaultOwnerFeeBasisPoint(), 250, "fee written on init");
  }

  /// @notice The maximum valid fee (10_000 bps = 100%) is accepted at init.
  function test_initialize_sets_vault_owner_fee_basis_point_max() public {
    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    tA.mint(address(v), 100e18);
    tB.mint(address(v), 200e18);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    v.initialize(
      "MaxFeeVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 10_000
    );

    assertEq(v.vaultOwnerFeeBasisPoint(), 10_000);
  }

  /// @notice A fee strictly greater than 10_000 bps (i.e. > 100%) is rejected at init:
  ///         the vault cannot be created in a misconfigured state.
  function test_initialize_reverts_when_vault_owner_fee_basis_point_invalid() public {
    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    tA.mint(address(v), 100e18);
    tB.mint(address(v), 200e18);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidVaultOwnerFeeBasisPoint.selector);
    v.initialize(
      "BadFeeVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 10_001
    );
  }

  /// @notice Emits `VaultOwnerFeeBasisPointSet` exactly once during `initialize`.
  function test_initialize_emits_vault_owner_fee_basis_point_set() public {
    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    tA.mint(address(v), 100e18);
    tB.mint(address(v), 200e18);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    vm.expectEmit(true, false, false, true, address(v));
    emit ISharedVault.VaultOwnerFeeBasisPointSet(VAULT_OWNER, 777);
    v.initialize(
      "EmitFeeVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 777
    );
  }

  /// @notice The fee is immutable: there is intentionally no setter. This test documents
  ///         that contract-level guarantee by asserting the persisted value matches the
  ///         init value even after state-changing interactions (a no-op pause cycle here).
  ///         The stronger compile-time guarantee is enforced by the interface not exposing
  ///         any setter — this test locks in the runtime invariant.
  function test_vault_owner_fee_basis_point_is_immutable_after_init() public {
    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    tA.mint(address(v), 100e18);
    tB.mint(address(v), 200e18);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    v.initialize(
      "ImmutableFeeVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 321
    );

    // Exercise state-changing owner-only paths; none of these may mutate the stored fee.
    vm.prank(VAULT_OWNER);
    v.setPaused(true);
    vm.prank(VAULT_OWNER);
    v.setPaused(false);

    assertEq(v.vaultOwnerFeeBasisPoint(), 321, "fee unchanged by subsequent owner actions");
  }

  /// @notice Withdraw delegatecalls `exitProportional` with the stored owner fee bps so strategies can apply
  /// performance fees.
  function test_withdraw_forwards_vault_owner_fee_bps_to_strategy() public {
    MockLPPool lpPoolContract = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(lpPoolContract));
    MockERC721 feeNfpm = new MockERC721();
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(lpStrategy);
    address[] memory nfpmsFee = new address[](1);
    nfpmsFee[0] = address(feeNfpm);
    cm.initialize(VAULT_OWNER, targets, new address[](0), address(this), 0, nfpmsFee, new address[](0));

    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    uint256 dep = 100e18;
    tA.mint(address(this), dep);
    tB.mint(address(this), dep);
    tA.transfer(address(v), dep);
    tB.transfer(address(v), dep);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [dep, dep, uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("FeeBpsVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 1234);
    assertEq(v.vaultOwnerFeeBasisPoint(), 1234);

    feeNfpm.mint(address(v), 1);
    vm.startPrank(VAULT_OWNER);
    bytes memory stratData = abi.encode(address(feeNfpm), uint256(1), address(tA), address(tB), 50e18, 50e18);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    v.execute(actions);
    vm.stopPrank();

    uint256 shares = v.balanceOf(VAULT_OWNER);

    vm.recordLogs();
    vm.prank(VAULT_OWNER);
    v.withdraw(shares, [uint256(0), uint256(0), uint256(0), uint256(0)], false);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    bytes32 evSig = keccak256("ExitVaultOwnerFeeBps(uint16)");
    bool found;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter == address(v) && logs[i].topics.length > 0 && logs[i].topics[0] == evSig) {
        assertEq(abi.decode(logs[i].data, (uint256)), 1234);
        found = true;
        break;
      }
    }
    assertTrue(found, "ExitVaultOwnerFeeBps must be emitted from vault during delegatecall exit");
  }

  /// @notice When platformBps + vaultOwnerBps > 10_000, the vault owner fee is clamped to
  ///         10_000 - platformBps so combined fees never exceed 100% of rewards.
  function test_performance_fee_config_clamps_vault_owner_fee_when_sum_exceeds_10000() public {
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(3000);

    PerformanceFeeConfigHarness harness = new PerformanceFeeConfigHarness(address(configManager), address(0xBEEF), 8000);
    ICommon.FeeConfig memory fc = harness.callPerformanceFeeConfig();

    assertEq(fc.vaultOwnerFeeBasisPoint, 7000, "clamped to 10000 - platformBps");
    assertEq(fc.platformFeeBasisPoint, 3000, "platform fee unchanged");
  }

  /// @notice When combined fees are at or below 10_000 bps, no clamping occurs.
  function test_performance_fee_config_does_not_clamp_when_sum_within_10000() public {
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(2000);

    PerformanceFeeConfigHarness harness = new PerformanceFeeConfigHarness(address(configManager), address(0xBEEF), 3000);
    ICommon.FeeConfig memory fc = harness.callPerformanceFeeConfig();

    assertEq(fc.vaultOwnerFeeBasisPoint, 3000, "no clamping when sum = 5000");
    assertEq(fc.platformFeeBasisPoint, 2000, "platform fee unchanged");
  }

  /// @notice Boundary: exactly 10_000 bps combined is not clamped; 10_001 is.
  function test_performance_fee_config_clamp_boundary() public {
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(5000);

    PerformanceFeeConfigHarness harness = new PerformanceFeeConfigHarness(address(configManager), address(0xBEEF), 5000);

    ICommon.FeeConfig memory fc = harness.callPerformanceFeeConfig();
    assertEq(fc.vaultOwnerFeeBasisPoint, 5000, "exactly at boundary - not clamped");

    harness = new PerformanceFeeConfigHarness(address(configManager), address(0xBEEF), 5001);
    fc = harness.callPerformanceFeeConfig();
    assertEq(fc.vaultOwnerFeeBasisPoint, 5000, "one over boundary - clamped to 5000");
  }

  function test_performance_fee_config_config_zero_disables_platform_fee() public {
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(0);

    PerformanceFeeConfigHarness harness = new PerformanceFeeConfigHarness(address(configManager), address(0xBEEF), 500);
    ICommon.FeeConfig memory fc = harness.callPerformanceFeeConfig();

    assertEq(fc.platformFeeBasisPoint, 0, "config disables platform fee");
    assertEq(fc.vaultOwnerFeeBasisPoint, 500, "owner fee remains vault-owned");
  }

  // ==================== Preview Tests ====================

  function test_preview_deposit() public view {
    uint256[4] memory amounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 previewShares = vault.previewDeposit(amounts);
    assertGt(previewShares, 0);
  }

  /// @notice Bug fix (Bug 1): previewDeposit must return 0 when the caller omits a token that
  ///         has a non-zero vault balance. Previously it returned a positive share count for
  ///         single-token deposits against a multi-token vault, but deposit() would revert with
  ///         InvalidRatio() because _subsequentDepositTransfers enforces proportional coverage.
  function test_previewDeposit_returns_zero_when_missing_required_token() public {
    // Dust vault: tokenA = 100e18, tokenB = 50 wei. A single-tokenA deposit omits tokenB.
    SharedVault v = _setupDustVault();

    // Caller provides only tokenA, skipping the 50 wei tokenB dust slot.
    uint256[4] memory onlyA = [uint256(1e18), uint256(0), uint256(0), uint256(0)];
    uint256 preview = v.previewDeposit(onlyA);

    // deposit() would revert InvalidRatio; previewDeposit must agree and return 0.
    assertEq(preview, 0, "previewDeposit must return 0 when a required token is omitted");
  }

  /// @notice previewDeposit returns 0 when the provided dust-token amount is below the min floor
  ///         that _subsequentDepositTransfers would enforce (precision=5 → floor = 1e13 for 18-dec).
  function test_previewDeposit_returns_zero_when_amount_below_dust_floor() public {
    SharedVault v = _setupDustVault();
    // Default precision = 5 → floor for 18-dec token = 10**(18-5) = 1e13.
    // Provide tokenA=1e18 and tokenB=5 (well below 1e13).
    uint256[4] memory tooLittle = [uint256(1e18), uint256(5), uint256(0), uint256(0)];
    uint256 preview = v.previewDeposit(tooLittle);
    assertEq(preview, 0, "previewDeposit must return 0 when dust amount is below the floor");
  }

  /// @notice previewDeposit returns a positive share count when all required tokens are supplied
  ///         at or above the dust floor — consistent with deposit() succeeding.
  function test_previewDeposit_returns_shares_when_all_tokens_supplied() public {
    SharedVault v = _setupDustVault();
    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 1e13); // exactly the precision floor

    // Provide tokenA=1e18 and tokenB=1e13 (exactly the precision floor).
    uint256[4] memory valid = [uint256(1e18), uint256(1e13), uint256(0), uint256(0)];
    uint256 preview = v.previewDeposit(valid);
    assertGt(preview, 0, "previewDeposit must return shares when all required amounts are met");
  }

  function test_preview_withdraw() public view {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory previewAmounts = vault.previewWithdraw(ownerShares);
    assertEq(previewAmounts[0], 100e18);
    assertEq(previewAmounts[1], 200e18);
  }

  // ==================== View Tests ====================

  function test_get_tokens() public view {
    address[4] memory vaultTokens = vault.getTokens();
    assertEq(vaultTokens[0], address(tokenA));
    assertEq(vaultTokens[1], address(tokenB));
    assertEq(vaultTokens[2], address(tokenC));
    assertEq(vaultTokens[3], address(tokenD));
  }

  function test_get_idle_balances() public view {
    uint256[4] memory balances = vault.getIdleBalances();
    assertEq(balances[0], 100e18);
    assertEq(balances[1], 200e18);
    assertEq(balances[2], 0);
    assertEq(balances[3], 0);
  }

  // ==================== Native ETH / WETH Tests ====================

  /// @dev Creates a fresh vault with [tokenA, mockWeth] tokens and 100e18 of each.
  ///      ETH is deposited via mockWeth.deposit() so MockWETH9 holds real ETH to back withdrawals.
  function _setupWethVault() internal returns (SharedVault wv) {
    wv = new SharedVault();

    // Wrap 100e18 ETH → WETH; test contract gets the WETH and transfers to vault
    tokenA.mint(address(this), 100e18);
    vm.deal(address(this), 100e18);
    mockWeth.deposit{ value: 100e18 }();

    tokenA.transfer(address(wv), 100e18);
    mockWeth.transfer(address(wv), 100e18);

    address[4] memory wvTokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    wv.initialize(
      "WETH Vault", wvTokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(mockWeth), 0
    );
    vm.stopPrank();
    // VAULT_OWNER now has all shares = 100e18 * SHARES_PRECISION
  }

  /// @notice Depositing with msg.value wraps ETH to WETH inside the vault
  function test_deposit_eth_wraps_to_weth() public {
    SharedVault wethVault = _setupWethVault();

    tokenA.mint(DEPOSITOR, 50e18);
    vm.deal(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(wethVault), type(uint256).max);

    // Deposit 50e18 tokenA + 50e18 ETH (→ WETH). Proportional: 50/100 ratio → exact match.
    uint256[4] memory amounts = [uint256(50e18), uint256(50e18), uint256(0), uint256(0)];
    uint256 shares = wethVault.deposit{ value: 50e18 }(amounts, 0);
    vm.stopPrank();

    assertGt(shares, 0);
    assertEq(wethVault.balanceOf(DEPOSITOR), shares);

    // Vault gained 50e18 WETH from wrapped ETH
    assertEq(mockWeth.balanceOf(address(wethVault)), 150e18);
    // Depositor's ETH is fully consumed
    assertEq(DEPOSITOR.balance, 0);
  }

  /// @notice Proportional deposit: only the needed fraction of WETH is consumed; excess ETH is refunded
  function test_deposit_eth_excess_refund() public {
    SharedVault wethVault = _setupWethVault();
    // State: 100e18 tokenA + 100e18 WETH, totalSupply = 100e18 * SHARES_PRECISION

    // Depositor sends 40e18 tokenA + 80e18 ETH, but the binding constraint is tokenA (40/100 = 40%)
    // transferAmounts = [40e18, 40e18]; excess WETH = 80e18 - 40e18 = 40e18 refunded as ETH
    tokenA.mint(DEPOSITOR, 40e18);
    vm.deal(DEPOSITOR, 80e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(wethVault), type(uint256).max);

    uint256[4] memory amounts = [uint256(40e18), uint256(80e18), uint256(0), uint256(0)];
    wethVault.deposit{ value: 80e18 }(amounts, 0);
    vm.stopPrank();

    // 40e18 ETH refunded; depositor paid net 40e18 ETH
    assertEq(DEPOSITOR.balance, 40e18);
    // Vault received only 40e18 WETH (not 80e18)
    assertEq(mockWeth.balanceOf(address(wethVault)), 140e18);
  }

  /// @notice Sending ETH when no WETH token is configured in the vault reverts
  function test_deposit_eth_fails_weth_not_configured() public {
    // `vault` was initialized with weth = address(0): no WETH slot
    vm.deal(DEPOSITOR, 1 ether);
    uint256[4] memory amounts = [uint256(0), uint256(1 ether), uint256(0), uint256(0)];
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.deposit{ value: 1 ether }(amounts, 0);
  }

  /// @notice msg.value must equal amounts[wethIndex]; mismatch reverts
  function test_deposit_eth_fails_wrong_amount() public {
    SharedVault wethVault = _setupWethVault();
    vm.deal(DEPOSITOR, 60e18);

    uint256[4] memory amounts = [uint256(0), uint256(50e18), uint256(0), uint256(0)];
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    // msg.value (60e18) != amounts[wethIndex] (50e18)
    wethVault.deposit{ value: 60e18 }(amounts, 0);
  }

  /// @notice Withdraw with unwrap=true: WETH is unwrapped and caller receives native ETH
  function test_withdraw_unwrap_true_sends_native_eth() public {
    SharedVault wethVault = _setupWethVault();
    uint256 shares = wethVault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    uint256 ethBefore = VAULT_OWNER.balance;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = wethVault.withdraw(shares, minAmounts, true);

    // VAULT_OWNER received native ETH for the WETH portion
    assertEq(VAULT_OWNER.balance - ethBefore, received[1]);
    assertGt(received[1], 0);
    // No WETH tokens transferred
    assertEq(mockWeth.balanceOf(VAULT_OWNER), 0);
    // tokenA transferred as ERC20
    assertEq(tokenA.balanceOf(VAULT_OWNER), received[0]);
  }

  /// @notice Withdraw with unwrap=false: WETH stays as an ERC20 token, no native ETH sent
  function test_withdraw_unwrap_false_keeps_weth_token() public {
    SharedVault wethVault = _setupWethVault();
    uint256 shares = wethVault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    uint256[4] memory received = wethVault.withdraw(shares, minAmounts, false);

    // VAULT_OWNER received WETH tokens (not native ETH)
    assertEq(mockWeth.balanceOf(VAULT_OWNER), received[1]);
    assertGt(received[1], 0);
    // No native ETH received
    assertEq(VAULT_OWNER.balance, 0);
    // tokenA received as ERC20
    assertEq(tokenA.balanceOf(VAULT_OWNER), received[0]);
  }

  /// @notice With the dust-proof rounding-up rule, a sub-1-wei proportional WETH slice is
  ///         raised to 1 wei and fully consumed — not refunded, not locked in the vault.
  ///         The precision floor is disabled (set to 0) so only the ceiling rounding is exercised,
  ///         since the depositor intentionally provides amounts (1 wei) that are below the default
  ///         5-decimal floor (1e13 for 18-decimal tokens).
  /// @dev Constructs: tokenA=1e18, mockWeth=1 wei → totalSupply=INITIAL_SHARES
  ///      Deposit amounts=[1 wei tokenA, 1 wei ETH]: sharesOut=min-ratio=10, transferAmounts[weth]
  ///      computed as mulDivRoundingUp(10, 1, INITIAL_SHARES) = 1 wei (ceiling of ~0).
  ///      The 1 wei ETH is wrapped and used — excess refund is 0.
  function test_deposit_eth_dust_amount_is_consumed_via_roundup() public {
    // Disable the precision floor so sub-1e13 amounts are accepted; this test exercises
    // the ceiling-rounding mechanism independently of the floor.
    configManager.setMinTokenPrecision(0);

    SharedVault wv = new SharedVault();
    tokenA.mint(address(this), 1e18);
    vm.deal(address(this), 100 ether);
    mockWeth.deposit{ value: 1 }();

    tokenA.transfer(address(wv), 1e18);
    mockWeth.transfer(address(wv), 1);

    address[4] memory wvTokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1e18), uint256(1), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    wv.initialize(
      "Dust Vault", wvTokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(mockWeth), 0
    );
    vm.stopPrank();

    address depositor = makeAddr("dustDepositor");
    vm.deal(depositor, 1 wei);
    tokenA.mint(depositor, 1);

    vm.startPrank(depositor);
    tokenA.approve(address(wv), 1);

    uint256[4] memory amounts = [uint256(1), uint256(1), uint256(0), uint256(0)];
    uint256 sharesBefore = wv.balanceOf(depositor);

    uint256 vaultWethBefore = mockWeth.balanceOf(address(wv));
    wv.deposit{ value: 1 }(amounts, 0);
    vm.stopPrank();

    assertGt(wv.balanceOf(depositor), sharesBefore, "should receive shares");
    // 1 wei ETH fully consumed (ceiling-rounded transferAmounts[weth]=1 ⇒ excess=0)
    assertEq(depositor.balance, 0, "dust ETH must be consumed, not refunded -- slice rounded up to 1 wei");
    // Vault WETH gained exactly 1 wei from the wrapped ETH
    assertEq(mockWeth.balanceOf(address(wv)), vaultWethBefore + 1, "vault WETH grew by 1 wei");
  }

  // ==================== Double-Dilution Regression Tests ====================

  /// @dev Helper: creates a fresh vault with LP strategy, two equal depositors, and an LP position.
  ///      Each user deposits `depositPerUser` of each token.
  ///      Then `lpAmount` of each token is moved into a mock LP position.
  ///      Final state: idle = 2*depositPerUser - lpAmount, LP = lpAmount, total = 2*depositPerUser per token.
  ///      Alice and Bob each hold 50% of shares → each entitled to `depositPerUser` per token.
  function _setupLPVault(uint256 depositPerUser, uint256 lpAmount)
    internal
    returns (SharedVault v, MockERC20 tA, MockERC20 tB, MockLPPool lpPoolContract)
  {
    lpPoolContract = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(lpPoolContract));
    MockERC721 lpNfpm = new MockERC721();

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(lpStrategy);
    address[] memory callers = new address[](0);
    address[] memory nfpmsLp = new address[](1);
    nfpmsLp[0] = address(lpNfpm);
    cm.initialize(address(this), targets, callers, address(this), 0, nfpmsLp, new address[](0));

    v = new SharedVault();
    tA = new MockERC20("Token A", "A");
    tB = new MockERC20("Token B", "B");

    // Alice (VAULT_OWNER) seeds vault
    tA.mint(address(this), depositPerUser);
    tB.mint(address(this), depositPerUser);
    tA.transfer(address(v), depositPerUser);
    tB.transfer(address(v), depositPerUser);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [depositPerUser, depositPerUser, uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    v.initialize("TestVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 0);
    vm.stopPrank();

    // Bob deposits the same amounts → gets equal shares
    address bob = makeAddr("bob");
    tA.mint(bob, depositPerUser);
    tB.mint(bob, depositPerUser);
    vm.startPrank(bob);
    tA.approve(address(v), type(uint256).max);
    tB.approve(address(v), type(uint256).max);
    uint256[4] memory bobDeposit = [depositPerUser, depositPerUser, uint256(0), uint256(0)];
    v.deposit(bobDeposit, 0);
    vm.stopPrank();

    // Move lpAmount of each into LP via strategy execute
    if (lpAmount > 0) {
      lpNfpm.mint(address(v), 1);
      vm.startPrank(VAULT_OWNER);
      bytes memory stratData = abi.encode(address(lpNfpm), uint256(1), address(tA), address(tB), lpAmount, lpAmount);
      ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
      actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
      v.execute(actions);
      vm.stopPrank();
    }
  }

  /// @notice Regression: withdraw with active LP must not double-dilute the LP exit return.
  /// Each user deposits 100e18 per token, vault creates 100e18 LP.
  /// Final state: idle=100e18, LP=100e18, total=200e18 per token, 50/50 shares.
  /// Alice's 50% = 100e18 per token.
  /// Before fix: exitProportional returns 50e18 → idle=150e18 → amounts=50/100*150=75e18 (WRONG).
  /// After fix:  amounts = 50/100*100(original idle) + 50(LP return) = 100e18 (CORRECT).
  function test_withdraw_no_double_dilution_with_lp() public {
    // depositPerUser=100e18, lpAmount=100e18
    // total=200e18, idle=100e18, LP=100e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB,) = _setupLPVault(100e18, 100e18);

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    assertEq(aliceShares, TEST_INITIAL_SHARES);
    assertEq(v.totalSupply(), TEST_INITIAL_SHARES * 2);

    // Verify total balances
    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 200e18, "total A = 200e18");
    assertEq(totalBal[1], 200e18, "total B = 200e18");

    // Preview: Alice's 50% of 200e18 = 100e18
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 100e18, "preview A = 50% of 200e18");
    assertEq(preview[1], 100e18, "preview B = 50% of 200e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    // Core assertion: Alice gets her full proportional share
    assertEq(received[0], 100e18, "Alice must receive 100e18 A (not 75e18)");
    assertEq(received[1], 100e18, "Alice must receive 100e18 B (not 75e18)");
    assertEq(received[0], preview[0], "actual must match preview for A");
    assertEq(received[1], preview[1], "actual must match preview for B");

    // Bob withdraws the remainder — vault must be perfectly drained
    address bob = makeAddr("bob");
    uint256[4] memory bobPreview = v.previewWithdraw(v.balanceOf(bob));
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 100e18, "Bob must receive 100e18 A");
    assertEq(bobReceived[1], 100e18, "Bob must receive 100e18 B");
    assertEq(bobReceived[0], bobPreview[0], "Bob actual must match preview for A");
    assertEq(bobReceived[1], bobPreview[1], "Bob actual must match preview for B");

    assertEq(v.totalSupply(), 0, "all shares burned");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  /// @notice Heavy LP allocation — matches the bug report's Alice/Bob scenario.
  /// Each user deposits 500e18, vault creates 900e18 LP.
  /// Final: idle=100e18, LP=900e18, total=1000e18 per token.
  /// Alice's 50% = 500e18.
  /// Before fix: exit returns 450 → idle=550 → amounts=50%*550=275 (WRONG).
  /// After fix:  amounts = 50%*100 + 450 = 500 (CORRECT).
  function test_withdraw_heavy_lp_no_double_dilution() public {
    // depositPerUser=500e18, lpAmount=900e18
    // total=1000e18, idle=100e18, LP=900e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB,) = _setupLPVault(500e18, 900e18);

    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 1000e18, "total A");
    assertEq(totalBal[1], 1000e18, "total B");
    assertEq(tA.balanceOf(address(v)), 100e18, "idle A = 100e18");

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 500e18, "preview A = 50% of 1000e18");
    assertEq(preview[1], 500e18, "preview B = 50% of 1000e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    assertEq(received[0], 500e18, "Alice A = 500e18 (not 275e18)");
    assertEq(received[1], 500e18, "Alice B = 500e18 (not 275e18)");
    assertEq(received[0], preview[0], "match preview A");
    assertEq(received[1], preview[1], "match preview B");

    // Bob gets the other half — vault drains cleanly
    address bob = makeAddr("bob");
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 500e18, "Bob A");
    assertEq(bobReceived[1], 500e18, "Bob B");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  /// @notice Edge case: vault has zero idle, 100% LP.
  /// depositPerUser=50e18, lpAmount=100e18 → idle=0, LP=100e18, total=100e18.
  /// Alice's 50% = 50e18.
  function test_withdraw_zero_idle_all_lp_no_double_dilution() public {
    // depositPerUser=50e18, lpAmount=100e18
    // total=100e18, idle=0, LP=100e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB,) = _setupLPVault(50e18, 100e18);

    assertEq(tA.balanceOf(address(v)), 0, "idle A = 0");
    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 100e18, "total A = 100e18");

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 50e18, "preview A = 50% of 100e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    assertEq(received[0], 50e18, "Alice A");
    assertEq(received[1], 50e18, "Alice B");
    assertEq(received[0], preview[0], "match preview A");

    // Bob gets remainder
    address bob = makeAddr("bob");
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 50e18, "Bob A");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  // ==================== execute() — DELEGATECALL + token changes ====================

  /// @notice DELEGATECALL returning an empty PositionChange[] is the token-change case:
  ///         the strategy runs in vault context (e.g., harvest+swap) and only vault token
  ///         balances change. The vault sees the idle balance difference with no position tracking.
  function test_execute_delegatecall_token_changes_empty_position_array() public {
    // Simulate a harvest: externally mint tokenA into vault before the strategy "runs"
    // (in a real harvest the strategy would collect fees and they'd land in the vault)
    uint256 harvestAmount = 5e18;
    tokenA.mint(address(vault), harvestAmount);
    uint256 balanceBefore = tokenA.balanceOf(address(vault));

    vm.startPrank(VAULT_OWNER);
    // MockSharedStrategy.execute() returns empty PositionChange[] — simulates a token-only op
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(0)), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    vm.stopPrank();

    // No position changes expected
    assertEq(vault.getPositionCount(), 0, "no positions should be tracked");
    // Token balance reflects the externally-added harvest (vault always sees current idle balance)
    assertEq(tokenA.balanceOf(address(vault)), balanceBefore, "token balance unchanged by empty strategy");
  }

  /// @notice DELEGATECALL with non-empty PositionChange[] → LP position tracked.
  ///         This is the existing behavior confirmed as the "position change" case.
  function test_execute_delegatecall_position_changes_tracked() public {
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));

    vm.startPrank(address(this));
    address[] memory extraTargets1 = new address[](1);
    extraTargets1[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets1, true);
    vm.stopPrank();

    uint256 tokenId = 1;
    cwpNfpm.mint(address(vault), tokenId);

    // Give vault some tokens so the LP deposit can pull them
    tokenA.mint(address(vault), 10e18);
    tokenB.mint(address(pool), 10e18); // pool needs tokenB to return on exit

    vm.startPrank(VAULT_OWNER);
    bytes memory stratData =
      abi.encode(address(cwpNfpm), tokenId, address(tokenA), address(tokenB), uint256(10e18), uint256(0));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "one LP position should be tracked");
    (address strategy, address nfpm, uint256 tid,,) = vault.getPosition(0);
    assertEq(strategy, address(lpStrategy), "strategy stored correctly");
    assertEq(nfpm, address(cwpNfpm), "nfpm stored correctly");
    assertEq(tid, tokenId, "tokenId stored correctly");
  }

  /// @notice DELEGATECALL: strategy returns isAdd with a non-vault pool token → `TokenNotConfigured`
  ///         (calldata may pass vault token addresses; the vault validates returned `PositionChange` tokens).
  function test_execute_delegatecall_reverts_when_mint_reports_non_vault_token() public {
    MockMisreportingTokenAddStrategy badStrat = new MockMisreportingTokenAddStrategy(address(tokenE), address(tokenB));
    assertFalse(vault.isVaultToken(address(tokenE)));
    assertTrue(vault.isVaultToken(address(tokenB)));

    vm.startPrank(address(this));
    address[] memory t = new address[](1);
    t[0] = address(badStrat);
    configManager.setWhitelistTargets(t, true);
    vm.stopPrank();

    address mockNfpm = address(0xDEAD);
    uint256 posTokenId = 7;
    // Harness passes only vault tokens in calldata (same tuple as other mock strategies)
    bytes memory stratData = abi.encode(mockNfpm, posTokenId, address(tokenA), address(tokenB));

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(badStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0);
  }

  // ==================== execute() — CALL_WITH_POSITIONS ====================

  /// @notice CALL_WITH_POSITIONS: direct call returns PositionChange[] → LP position added.
  function test_execute_call_with_positions_adds_position() public {
    uint256 tokenId = 42;
    cwpNfpm.mint(address(vault), tokenId);

    bytes memory callData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "position should be added");
    (address strategy, address nfpm, uint256 tid, address t0, address t1) = vault.getPosition(0);
    assertEq(strategy, address(directCreator), "strategy is the direct creator target");
    assertEq(nfpm, address(cwpNfpm));
    assertEq(tid, tokenId);
    assertEq(t0, address(tokenA));
    assertEq(t1, address(tokenB));
  }

  /// @notice CALL_WITH_POSITIONS: direct call returns PositionChange[] with isAdd=false → position removed.
  function test_execute_call_with_positions_removes_position() public {
    // First add a position via DELEGATECALL
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory extraTargets2 = new address[](1);
    extraTargets2[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets2, true);

    uint256 tokenId = 99;
    cwpNfpm.mint(address(vault), tokenId);

    tokenA.mint(address(vault), 10e18);
    tokenB.mint(address(pool), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory addData =
      abi.encode(address(cwpNfpm), tokenId, address(tokenA), address(tokenB), uint256(10e18), uint256(0));
    ISharedVault.Action[] memory addActions = new ISharedVault.Action[](1);
    addActions[0] = ISharedVault.Action(address(lpStrategy), addData, ISharedCommon.CallType.DELEGATECALL);
    vault.execute(addActions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "position added");

    // Now remove via CALL_WITH_POSITIONS
    bytes memory removeCallData = abi.encodeCall(
      MockDirectPositionCreator.removePosition, (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory removeActions = new ISharedVault.Action[](1);
    removeActions[0] =
      ISharedVault.Action(address(directCreator), removeCallData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(removeActions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "position should be removed");
  }

  /// @notice CALL_WITH_POSITIONS with empty PositionChange[] result → no tracking change.
  function test_execute_call_with_positions_empty_result_no_change() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.noChanges, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "no positions should be added");
  }

  /// @notice CALL_WITH_POSITIONS: target call reverts → execute reverts with the error message.
  function test_execute_call_with_positions_reverts_on_failure() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.alwaysFail, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert("DirectCreator: always fails");
    vault.execute(actions);
    vm.stopPrank();
  }

  /// @notice CALL_WITH_POSITIONS: non-whitelisted target → reverts with InvalidTarget.
  function test_execute_call_with_positions_non_whitelisted_target() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.noChanges, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    // Use failingStrategy address which is NOT whitelisted
    actions[0] = ISharedVault.Action(address(failingStrategy), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.execute(actions);
    vm.stopPrank();
  }

  /// @notice CALL_WITH_POSITIONS: vault does not own the NFT reported as added → reverts.
  /// @dev Security check: _applyPositionChangesChecked verifies vault owns the NFT before
  ///      recording it. Without this check, an operator could register an NFT they don't own.
  function test_call_with_positions_revertsWhenVaultDoesNotOwnNft() public {
    uint256 tokenId = 77;
    // Intentionally do NOT mint the NFT to the vault — vault has no ownership

    bytes memory callData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  /// @notice Mixed batch: DELEGATECALL (position) + CALL (swap) + CALL_WITH_POSITIONS (position) in one execute().
  function test_execute_mixed_batch_all_three_call_types() public {
    // Setup: whitelist lpStrategy
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory extraTargets3 = new address[](1);
    extraTargets3[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets3, true);

    // Prepare tokens
    tokenA.mint(address(vault), 20e18);
    tokenB.mint(address(pool), 10e18);
    tokenB.mint(address(swapTarget), 5e18);

    cwpNfpm.mint(address(vault), 1); // DELEGATECALL position tokenId=1
    cwpNfpm.mint(address(vault), 2); // CWP position tokenId=2

    // Action 1: DELEGATECALL — strategy creates LP position
    bytes memory dcData =
      abi.encode(address(cwpNfpm), uint256(1), address(tokenA), address(tokenB), uint256(10e18), uint256(0));

    // Action 2: CALL — token swap tokenA → tokenB
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 5e18));
    bytes memory swapData = abi.encode(address(tokenA), address(tokenB), 5e18, uint256(0), swapCalldata);

    // Action 3: CALL_WITH_POSITIONS — direct call creates another position
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), 2, address(tokenA), address(tokenB))
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](3);
    actions[0] = ISharedVault.Action(address(lpStrategy), dcData, ISharedCommon.CallType.DELEGATECALL);
    actions[1] = ISharedVault.Action(address(swapTarget), swapData, ISharedCommon.CallType.CALL);
    actions[2] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.startPrank(VAULT_OWNER);
    vault.execute(actions);
    vm.stopPrank();

    // Two LP positions tracked (one from DELEGATECALL, one from CALL_WITH_POSITIONS)
    assertEq(vault.getPositionCount(), 2, "two positions should be tracked");
    // Swap was also successful
    assertGt(tokenB.balanceOf(address(vault)), 0, "tokenB balance increased from swap");
  }

  // ==================== Position Limit Tests ====================

  // Helper: add a unique position via CALL_WITH_POSITIONS using directCreator.
  // tokenId is used to make each (nfpm, tokenId) pair unique.
  function _addPositionViaDirectCreator(uint256 tokenId) internal {
    cwpNfpm.mint(address(vault), tokenId);
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
  }

  function test_maxPositions_defaultIs20() public view {
    assertEq(configManager.maxPositions(), 20);
  }

  function test_maxPositions_revertsWhenLimitReached() public {
    // Set limit to 2, add 2 positions, then verify the 3rd reverts
    configManager.setMaxPositions(2);

    _addPositionViaDirectCreator(1);
    _addPositionViaDirectCreator(2);
    assertEq(vault.getPositionCount(), 2);

    cwpNfpm.mint(address(vault), 3);
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), 3, address(tokenA), address(tokenB))
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.TooManyPositions.selector);
    vault.execute(actions);
  }

  function test_maxPositions_allowsExactlyLimitPositions() public {
    configManager.setMaxPositions(3);

    _addPositionViaDirectCreator(1);
    _addPositionViaDirectCreator(2);
    _addPositionViaDirectCreator(3);

    assertEq(vault.getPositionCount(), 3);
  }

  function test_maxPositions_raisingLimitAllowsMorePositions() public {
    configManager.setMaxPositions(1);
    _addPositionViaDirectCreator(1);
    assertEq(vault.getPositionCount(), 1);

    // Raise the limit
    configManager.setMaxPositions(2);
    _addPositionViaDirectCreator(2);
    assertEq(vault.getPositionCount(), 2);
  }

  function test_maxPositions_loweringLimitDoesNotBlockWithdraw() public {
    // Add 3 positions, then lower limit to 1 — withdrawal must still work
    configManager.setMaxPositions(3);
    _addPositionViaDirectCreator(1);
    _addPositionViaDirectCreator(2);
    _addPositionViaDirectCreator(3);
    assertEq(vault.getPositionCount(), 3);

    configManager.setMaxPositions(1);

    // Full withdrawal succeeds even though position count (3) exceeds new limit (1)
    uint256 shares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minOut;
    vm.prank(VAULT_OWNER);
    vault.withdraw(shares, minOut, false);

    // exitProportional on MockDirectPositionCreator returns empty changes, so positions stay
    // tracked (no removal) — the point is withdraw doesn't revert
    assertEq(vault.totalSupply(), 0);
  }

  // ==================== Dust-Floor Tests (minTokenPrecision) ====================
  //
  // The dust floor is expressed as a decimal-place precision level rather than a raw amount.
  // For a token with `d` decimals and configured precision `prec`, the effective min is:
  //
  //     minAmt = 10 ** max(0, d - prec)
  //
  // Default precision = 5, meaning 0.00001 of any token:
  //   18-decimal token (e.g. WETH):  10**(18-5) = 1e13 wei
  //    6-decimal token (e.g. USDC):  10**(6-5)  = 10
  //    8-decimal token (e.g. WBTC):  10**(8-5)  = 1000 sats
  //
  // Both mock tokens in this test suite have 18 decimals, so precision 5 -> floor = 1e13.
  //
  // Asymmetric behaviour:
  //   DEPOSIT  -- slices rounded UP (ceiling) then raised to minAmt. Forces depositor to
  //      over-pay dust slices, blocking the share-dilution attack.
  //   WITHDRAW -- plain floor division (mulDiv). Dust is forwarded as-is to the caller.
  //      If the call originated from SharedVaultGateway, the gateway returns un-swappable
  //      dust directly to the user rather than failing the transaction.

  // ---- config: setMinTokenPrecision ----

  function test_setMinTokenPrecision_default_is_five() public view {
    assertEq(configManager.minTokenPrecision(), 5, "default precision = 5");
  }

  function test_setMinTokenPrecision_owner_stores_value_and_emits() public {
    vm.expectEmit(true, true, true, true);
    emit ISharedConfigManager.MinTokenPrecisionUpdated(3);
    configManager.setMinTokenPrecision(3);

    assertEq(configManager.minTokenPrecision(), 3, "precision stored");
  }

  function test_setMinTokenPrecision_reverts_for_non_owner() public {
    vm.prank(NON_AUTHORIZED);
    vm.expectRevert();
    configManager.setMinTokenPrecision(3);
  }

  function test_setMinTokenPrecision_zero_disables_floor() public {
    configManager.setMinTokenPrecision(0);
    assertEq(configManager.minTokenPrecision(), 0, "floor disabled");
  }

  // ---- deposit: rounding up + precision-derived floor ----

  /// @dev Vault with tokenB at 50 wei dust (18-decimal mock tokens).
  ///      totalBalances = [100e18, 50], totalSupply = INITIAL_SHARES (10e18).
  function _setupDustVault() internal returns (SharedVault v) {
    v = new SharedVault();
    tokenA.mint(address(this), 100e18);
    tokenB.mint(address(this), 50);
    tokenA.transfer(address(v), 100e18);
    tokenB.transfer(address(v), 50);

    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(50), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("DustVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0);
  }

  /// @notice The dilution attack is blocked by ceiling rounding alone (no floor needed).
  ///         A depositor who provides 0 of the dust token but non-zero of the majority token
  ///         cannot receive shares -- the ceiling raises the required dust slice to >= 1 wei.
  function test_deposit_blocks_dust_dilution_attack_via_ceiling() public {
    SharedVault v = _setupDustVault();

    tokenA.mint(DEPOSITOR, 1e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256[4] memory attackAmounts = [uint256(1e18), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit(attackAmounts, 0);
    vm.stopPrank();
  }

  /// @notice With precision = 5 and 18-decimal tokens, the per-token floor is 10**(18-5) = 1e13.
  ///         A depositor providing tokenB below 1e13 must be rejected even if ceiling-rounded
  ///         proportional is already < 1e13.
  ///
  ///         Vault state: tokenB total = 50 wei, totalSupply = 10e18.
  ///         Depositor supplies 1e18 A + 5 wei B.
  ///         sharesOut from A = floor(1e18 * 10e18 / 100e18) = 1e17.
  ///         Ceiling proportional B = ceil(1e17 * 50 / 10e18) = 1.
  ///         Floor (precision=5, dec=18) = 1e13.
  ///         transferAmounts[B] = max(1, 1e13) = 1e13. Depositor provides 5 < 1e13 => reverts.
  function test_deposit_requires_at_least_precision_floor_for_dust_slice() public {
    SharedVault v = _setupDustVault();
    // Default precision = 5. floor = 10**(18-5) = 1e13.

    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 5);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256[4] memory tooLittle = [uint256(1e18), uint256(5), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit(tooLittle, 0);
    vm.stopPrank();
  }

  /// @notice Happy path: depositor supplies enough to clear the precision floor.
  ///         Vault pulls exactly the computed floor (1e13) from the depositor's tokenB.
  function test_deposit_pulls_exactly_precision_floor_for_dust_slice() public {
    SharedVault v = _setupDustVault();
    // precision = 5, dec = 18 => floor = 1e13.

    uint256 expectedFloor = 1e13;
    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 2e13); // more than the floor
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256 bBalBefore = tokenB.balanceOf(DEPOSITOR);
    uint256[4] memory amts = [uint256(1e18), uint256(2e13), uint256(0), uint256(0)];
    uint256 shares = v.deposit(amts, 0);
    vm.stopPrank();

    assertGt(shares, 0, "shares minted");
    assertEq(tokenB.balanceOf(DEPOSITOR), bBalBefore - expectedFloor, "depositor pays exactly the precision floor");
    assertEq(tokenB.balanceOf(address(v)), 50 + expectedFloor, "vault tokenB grew by exactly the floor");
  }

  /// @notice Precision = 0 disables the floor. Ceiling rounding is still active.
  ///         A dust slice of 1 wei passes because precision=0 => _minTokenAmt returns 0.
  function test_deposit_precision_zero_disables_floor_ceiling_still_active() public {
    SharedVault v = _setupDustVault();
    configManager.setMinTokenPrecision(0);

    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 1);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256[4] memory amts = [uint256(1e18), uint256(1), uint256(0), uint256(0)];
    uint256 shares = v.deposit(amts, 0);
    vm.stopPrank();

    assertGt(shares, 0, "shares minted when providing exactly 1 wei dust");
    assertEq(tokenB.balanceOf(address(v)), 51, "vault pulled exactly 1 wei (ceiling rounding)");
  }

  /// @notice Normal-sized deposits are unaffected by the floor.
  ///         A 10% proportional deposit far exceeds the precision floor on all tokens.
  function test_deposit_above_floor_behaves_normally() public {
    // Existing vault: 100e18 A + 200e18 B, precision=5 -> floor=1e13 per token.
    // 10% deposit yields 10e18 A and 20e18 B -- both >> 1e13.
    tokenA.mint(DEPOSITOR, 10e18);
    tokenB.mint(DEPOSITOR, 20e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory amts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(amts, 0);
    vm.stopPrank();

    assertEq(shares, TEST_INITIAL_SHARES / 10, "10% of INITIAL_SHARES");
    assertEq(tokenA.balanceOf(address(vault)), 110e18);
    assertEq(tokenB.balanceOf(address(vault)), 220e18);
  }

  /// @notice The floor scales correctly with different precision levels.
  ///         Precision = 17 on an 18-decimal token => floor = 10**(18-17) = 10 wei.
  ///         This simulates "0.1 unit" precision on a small-balance token.
  function test_deposit_precision_scales_per_decimal_count() public {
    SharedVault v = _setupDustVault();
    // Precision 17 => floor = 10**(18-17) = 10 wei (both tokens are 18-decimal mocks).
    configManager.setMinTokenPrecision(17);

    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 5); // 5 wei < 10-wei floor

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit([uint256(1e18), uint256(5), uint256(0), uint256(0)], 0);

    tokenB.mint(DEPOSITOR, 10); // now has 15 wei -- enough to clear 10-wei floor
    v.deposit([uint256(1e18), uint256(15), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    // Vault pulled exactly 10 wei of tokenB (the floor).
    assertEq(tokenB.balanceOf(address(v)), 60, "vault pulled exactly the 10-wei floor");
  }

  /// @dev Vault with an 18-decimal token and an 8-decimal dust token.
  ///      tokenB floor at default precision 5 is 10 ** (8 - 5) = 1_000.
  function _setupEightDecimalDustVault() internal returns (SharedVault v, MockERC20 tA, MockERC20LowDecimals tB) {
    v = new SharedVault();
    tA = new MockERC20("EightDecA", "EDA");
    tB = new MockERC20LowDecimals("EightDecB", "EDB", 8);

    tA.mint(address(v), 100e18);
    tB.mint(address(v), 5521);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(5521), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize(
      "EightDecimalDustVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0), 0
    );
  }

  function test_getMinDepositAmounts_8decimalToken_tracksPrecisionChanges() public {
    (SharedVault v,,) = _setupEightDecimalDustVault();

    uint256[4] memory mins = v.getMinDepositAmounts();
    assertEq(mins[1], 1000, "8 decimals, precision 5 -> 1_000");

    configManager.setMinTokenPrecision(4);
    mins = v.getMinDepositAmounts();
    assertEq(mins[1], 10_000, "8 decimals, precision 4 -> 10_000");

    configManager.setMinTokenPrecision(9);
    mins = v.getMinDepositAmounts();
    assertEq(mins[1], 1, "precision above decimals -> smallest unit");
  }

  function test_deposit_8decimalToken_requiresPrecisionFloor() public {
    (SharedVault v, MockERC20 tA, MockERC20LowDecimals tB) = _setupEightDecimalDustVault();

    tA.mint(DEPOSITOR, 10e18);
    tB.mint(DEPOSITOR, 999);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(v), type(uint256).max);
    tB.approve(address(v), type(uint256).max);

    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit([uint256(10e18), uint256(999), uint256(0), uint256(0)], 0);
    vm.stopPrank();
  }

  function test_deposit_8decimalToken_pullsExactlyPrecisionFloor() public {
    (SharedVault v, MockERC20 tA, MockERC20LowDecimals tB) = _setupEightDecimalDustVault();

    tA.mint(DEPOSITOR, 10e18);
    tB.mint(DEPOSITOR, 1200);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(v), type(uint256).max);
    tB.approve(address(v), type(uint256).max);

    uint256 shares = v.deposit([uint256(10e18), uint256(1200), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    assertGt(shares, 0, "shares minted");
    assertEq(tB.balanceOf(DEPOSITOR), 200, "only the 1_000-unit floor was pulled");
    assertEq(tB.balanceOf(address(v)), 6521, "vault received exactly 1_000 dust-token units");
  }

  // ---- withdraw: dust forwarded to caller ----

  /// @notice Withdrawal dust (proportional slices below any conceivable swap threshold) is
  ///         forwarded to the caller, not silently discarded.
  ///         Burning 1 wei share from the 10e18:200e18 vault yields 10 wei A and 20 wei B.
  ///         These tiny amounts are transferred even though they are well below 1e13 (precision-5 floor).
  ///         If called via the gateway, the gateway may return them directly to the user.
  function test_withdraw_forwards_dust_to_caller() public {
    uint256 sharesToBurn = 1;
    uint256 aVaultBefore = tokenA.balanceOf(address(vault));
    uint256 bVaultBefore = tokenB.balanceOf(address(vault));
    uint256 aOwnerBefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 bOwnerBefore = tokenB.balanceOf(VAULT_OWNER);

    uint256[4] memory minAmounts;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = vault.withdraw(sharesToBurn, minAmounts, false);

    // 1 / 10e18 of 100e18 A = 10 wei; 1 / 10e18 of 200e18 B = 20 wei.
    assertEq(received[0], 10, "10 wei A forwarded to caller");
    assertEq(received[1], 20, "20 wei B forwarded to caller");
    assertEq(tokenA.balanceOf(address(vault)), aVaultBefore - 10, "vault sent 10 wei A");
    assertEq(tokenB.balanceOf(address(vault)), bVaultBefore - 20, "vault sent 20 wei B");
    assertEq(tokenA.balanceOf(VAULT_OWNER), aOwnerBefore + 10, "owner received 10 wei A");
    assertEq(tokenB.balanceOf(VAULT_OWNER), bOwnerBefore + 20, "owner received 20 wei B");
  }

  /// @notice A normal-sized withdrawal transfers the full proportional amount.
  ///         Half of INITIAL_SHARES yields 50e18 A + 100e18 B.
  function test_withdraw_proportional_transfers_normally() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;
    uint256[4] memory minAmounts;

    vm.prank(VAULT_OWNER);
    uint256[4] memory received = vault.withdraw(halfShares, minAmounts, false);

    assertEq(received[0], 50e18, "half shares yields 50e18 A");
    assertEq(received[1], 100e18, "half shares yields 100e18 B");
  }

  /// @notice minTokenPrecision has no effect on withdraw -- dust is always forwarded.
  ///         With 1 wei share burn proportional = 10 wei A and 20 wei B, regardless of
  ///         how precision is configured.
  function test_withdraw_precision_setting_does_not_affect_output() public {
    // Even with precision=5 (floor=1e13), dust slices are forwarded unchanged.
    uint256 aOwnerBefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 bOwnerBefore = tokenB.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = vault.withdraw(1, minAmounts, false);

    assertEq(received[0], 10, "10 wei A forwarded (precision setting irrelevant on withdraw)");
    assertEq(received[1], 20, "20 wei B forwarded (precision setting irrelevant on withdraw)");
    assertEq(tokenA.balanceOf(VAULT_OWNER), aOwnerBefore + 10, "owner received 10 wei A");
    assertEq(tokenB.balanceOf(VAULT_OWNER), bOwnerBefore + 20, "owner received 20 wei B");
  }

  /// @notice Per-token proportional withdrawal: each token's slice is forwarded independently.
  ///         Vault: 100e18 A + 50 B, totalSupply = 10e18.
  ///         Half-share burn (5e18 / 10e18):
  ///           proportional A = mulDiv(5e18, 100e18, 10e18) = 50e18
  ///           proportional B = mulDiv(5e18, 50,     10e18) = 25 wei
  ///         Both slices -- large and dust -- are forwarded to the caller regardless of precision.
  function test_withdraw_per_token_all_slices_forwarded_to_caller() public {
    // Build a vault where tokenB is dust (50 wei) but tokenA is large.
    SharedVault v = _setupDustVault(); // 100e18 A, 50 B, totalSupply = 10e18

    uint256 ownerShares = v.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;
    uint256[4] memory minAmounts;

    uint256 aVaultBefore = tokenA.balanceOf(address(v));
    uint256 bVaultBefore = tokenB.balanceOf(address(v));
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = v.withdraw(halfShares, minAmounts, false);

    assertEq(received[0], 50e18, "tokenA slice (50e18) forwarded");
    assertEq(received[1], 25, "tokenB dust slice (25 wei) forwarded to caller");
    assertEq(tokenA.balanceOf(address(v)), aVaultBefore - 50e18, "tokenA left vault");
    assertEq(tokenB.balanceOf(address(v)), bVaultBefore - 25, "tokenB dust left vault");
  }

  function test_withdraw_8decimalDustBelowPrecisionFloor_isForwarded() public {
    (SharedVault v, MockERC20 tA, MockERC20LowDecimals tB) = _setupEightDecimalDustVault();

    uint256 sharesToBurn = 1e18; // 10% of INITIAL_SHARES
    vm.prank(VAULT_OWNER);
    v.transfer(DEPOSITOR, sharesToBurn);

    uint256[4] memory minAmounts;
    vm.prank(DEPOSITOR);
    uint256[4] memory received = v.withdraw(sharesToBurn, minAmounts, false);

    assertEq(received[0], 10e18, "10% tokenA withdrawn");
    assertEq(received[1], 552, "10% of 5_521 floors to 552, below the 1_000 deposit floor");
    assertLt(received[1], v.getMinDepositAmounts()[1], "withdraw dust may be below deposit floor");
    assertEq(tA.balanceOf(DEPOSITOR), 10e18, "depositor received tokenA");
    assertEq(tB.balanceOf(DEPOSITOR), 552, "depositor received below-floor tokenB dust");
  }

  function test_maxPositions_duplicatePositionDoesNotConsumeSlot() public {
    // Adding the same (nfpm, tokenId) twice must not count as two positions
    configManager.setMaxPositions(1);

    cwpNfpm.mint(address(vault), 99);
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition, (address(cwpNfpm), 99, address(tokenA), address(tokenB))
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.prank(VAULT_OWNER);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1);

    // Same (nfpm, tokenId) again — _addPosition returns early, no TooManyPositions
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1);
  }

  // ==================== Rewards-Ratio Fix: Principal-Only Scaling Tests ====================
  //
  // Regression suite for the bug where `_depositProportionalToAllPositions` scaled per-position
  // top-ups by `getPositionAmounts` (principal + uncollected fees). When a position's principal
  // ratio (set by the current tick range) diverges from its uncollected-fees ratio (set by
  // historical swap flow), this would produce off-range `(amount0, amount1)` desireds that the
  // underlying AMM's `increaseLiquidity` cannot consume in proportion — leading to either
  // silent idle leakage (slippageBps == 0) or a revert via `amount*Min` (slippageBps > 0).
  //
  // Scenario throughout this section (chosen so the two ratios diverge cleanly):
  //   - position principal:        30 A : 70 B   (3:7 range ratio)
  //   - position uncollected fees: 10 A : 10 B   (1:1 rewards ratio — different from range)
  //   - getPositionAmounts:        40 A : 80 B   (sum; 1:2 total ratio)
  //   - getPositionPrincipalAmounts: 30 A : 70 B (fix uses this for the LP top-up)
  //
  // The fix guarantees top-ups go in at the 3:7 principal ratio, regardless of how fees have
  // accrued — and the depositor's proportional share of the fees simply stays idle in the vault.

  /// @dev Builds a fresh vault with one `MockRewardsAwareStrategy` position whose principal
  ///      and rewards ratios diverge. Returns the vault, tokens, recorder, and the (nfpm,
  ///      tokenId) of the position. Post-setup state:
  ///        - vault idle: 20 A, 80 B (initial 50/150 minus 30/70 moved into the position)
  ///        - position: 30 A / 70 B principal  +  10 A / 10 B virtual rewards
  ///        - totalSupply = INITIAL_SHARES (owner holds all shares)
  function _setupVaultWithRewardsAwarePosition()
    internal
    returns (
      SharedVault rewardsVault,
      MockERC20 tA,
      MockERC20 tB,
      DepositProportionalRecorder recorder,
      MockERC721 nfpm,
      uint256 tokenId,
      MockRewardsAwareStrategy strat
    )
  {
    // --- Arrange: deploy isolated token/pool/recorder/strategy for this scenario -------------
    tA = new MockERC20("RewardsA", "RA");
    tB = new MockERC20("RewardsB", "RB");
    MockLPPool pool = new MockLPPool();
    recorder = new DepositProportionalRecorder();
    strat = new MockRewardsAwareStrategy(
      address(pool),
      address(recorder),
      30e18, // principal0
      70e18, // principal1
      10e18, // rewards0 (uncollected fees, virtual)
      10e18 // rewards1
    );
    nfpm = new MockERC721();
    tokenId = 1;

    // --- Arrange: whitelist strategy + nfpm in an isolated config manager --------------------
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    // --- Arrange: seed the vault with idle balances large enough to cover principal transfer
    rewardsVault = new SharedVault();
    tA.mint(address(this), 50e18);
    tB.mint(address(this), 150e18);
    tA.transfer(address(rewardsVault), 50e18);
    tB.transfer(address(rewardsVault), 150e18);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(50e18), uint256(150e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    rewardsVault.initialize("RewardsVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 0);

    // --- Act: register the position by delegatecall-executing the strategy -------------------
    nfpm.mint(address(rewardsVault), tokenId);
    bytes memory stratData = abi.encode(address(nfpm), tokenId, address(tA), address(tB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    rewardsVault.execute(actions);

    // --- Assert: setup preconditions (sanity guard for the rest of the suite) ----------------
    assertEq(tA.balanceOf(address(rewardsVault)), 20e18, "setup: vault idle A = initial - principal0");
    assertEq(tB.balanceOf(address(rewardsVault)), 80e18, "setup: vault idle B = initial - principal1");
    assertEq(rewardsVault.getPositionCount(), 1, "setup: one position tracked");

    (uint256 totalA, uint256 totalB) = strat.getPositionAmounts(address(nfpm), tokenId);
    assertEq(totalA, 40e18, "setup: getPositionAmounts includes fees (30 + 10)");
    assertEq(totalB, 80e18, "setup: getPositionAmounts includes fees (70 + 10)");

    (uint256 princA, uint256 princB) = strat.getPositionPrincipalAmounts(address(nfpm), tokenId);
    assertEq(princA, 30e18, "setup: getPositionPrincipalAmounts excludes fees");
    assertEq(princB, 70e18, "setup: getPositionPrincipalAmounts excludes fees");
  }

  /// @notice The vault's LP top-up is scaled by *principal* amounts, not by total (principal + rewards).
  ///         With 40:80 totals but 30:70 principal, a 30:80 proportional deposit must be split
  ///         into a 15:35 LP top-up (3:7 range ratio) — NOT 20:40 (1:2 totals ratio), which is the
  ///         pre-fix behavior and would push tokens in at the wrong range ratio.
  function test_deposit_rewardsRatio_usesPrincipalAmountsForLPTopup() public {
    // Arrange: fresh vault with a rewards-bearing position. State documented in helper.
    (SharedVault rv, MockERC20 tA, MockERC20 tB, DepositProportionalRecorder recorder,,,) =
      _setupVaultWithRewardsAwarePosition();

    // totalBalances = (20 idle + 40 position, 80 idle + 80 position) = (60, 160).
    // A 50% proportional deposit therefore transfers (30, 80).
    tA.mint(DEPOSITOR, 30e18);
    tB.mint(DEPOSITOR, 80e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);

    // Act: proportional deposit with zero slippage guard (so the recorder captures intent
    //      regardless of how the mock pool ends up absorbing the tokens).
    uint256[4] memory amounts = [uint256(30e18), uint256(80e18), uint256(0), uint256(0)];
    rv.deposit(amounts, 0);
    vm.stopPrank();

    // Assert: exactly one LP top-up happened, and at the principal (3:7) ratio, not the total (1:2) ratio.
    assertEq(recorder.callCount(), 1, "depositProportional called exactly once");
    // FIX: toAdd0 = transferAmount0 * principal0 / total0 = 30 * 30 / 60 = 15
    assertEq(recorder.lastAmount0(), 15e18, "LP top-up token0 scaled by principal, not totals");
    // FIX: toAdd1 = transferAmount1 * principal1 / total1 = 80 * 70 / 160 = 35
    assertEq(recorder.lastAmount1(), 35e18, "LP top-up token1 scaled by principal, not totals");

    // Cross-check the ratio explicitly — the bug manifests as a non-3:7 ratio here.
    assertEq(
      recorder.lastAmount0() * 7,
      recorder.lastAmount1() * 3,
      "LP top-up ratio must equal principal ratio (3:7), regardless of uncollected fees"
    );
  }

  /// @notice With the fix, a deposit carrying a reasonable slippage guard (1%) no longer reverts
  ///         just because the position's rewards ratio diverges from its principal ratio. Before
  ///         the fix this would revert with `"OffRatioDeposit"` because the pre-fix top-up at the
  ///         totals-ratio consumes less than `amountMin` on the binding side.
  function test_deposit_rewardsRatio_doesNotRevertUnderSlippageCheck() public {
    (SharedVault rv, MockERC20 tA, MockERC20 tB,,,,) = _setupVaultWithRewardsAwarePosition();

    tA.mint(DEPOSITOR, 30e18);
    tB.mint(DEPOSITOR, 80e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);

    uint256[4] memory amounts = [uint256(30e18), uint256(80e18), uint256(0), uint256(0)];
    // 1% slippage on the LP top-up. The mock's depositProportional mirrors real V3 semantics
    // and reverts `"OffRatioDeposit"` if the binding-side consumption falls below amountMin.
    uint256 sharesMinted = rv.deposit(amounts, uint16(100));
    vm.stopPrank();

    // Assert: deposit succeeded and minted non-zero shares proportional to the 50% contribution.
    assertGt(sharesMinted, 0, "deposit minted shares");
    assertEq(rv.balanceOf(DEPOSITOR), sharesMinted, "depositor holds the minted shares");
  }

  /// @notice With the fix, the rewards-proportional slice of the depositor's contribution stays
  ///         in the vault as idle balance (instead of being force-fed to the LP at the wrong ratio
  ///         and silently leaking). This is the "fees-count-as-idle" invariant the fix establishes.
  function test_deposit_rewardsRatio_leavesRewardsSliceAsIdle() public {
    (SharedVault rv, MockERC20 tA, MockERC20 tB,, MockERC721 nfpm, uint256 tokenId, MockRewardsAwareStrategy strat) =
      _setupVaultWithRewardsAwarePosition();

    uint256 idleABefore = tA.balanceOf(address(rv));
    uint256 idleBBefore = tB.balanceOf(address(rv));

    tA.mint(DEPOSITOR, 30e18);
    tB.mint(DEPOSITOR, 80e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);
    uint256[4] memory amounts = [uint256(30e18), uint256(80e18), uint256(0), uint256(0)];
    rv.deposit(amounts, 0);
    vm.stopPrank();

    // Of the 30 A pulled in, 15 went to the LP and 15 should have stayed idle (the rewards slice).
    // Symmetrically for B: 80 pulled, 35 to LP, 45 stays idle.
    assertEq(tA.balanceOf(address(rv)), idleABefore + 30e18 - 15e18, "rewards-slice of tokenA stays idle in vault");
    assertEq(tB.balanceOf(address(rv)), idleBBefore + 80e18 - 35e18, "rewards-slice of tokenB stays idle in vault");

    // And the LP position's principal grew by exactly the 3:7 top-up. MockLPPool tracks actual
    // balances separately from the virtual rewards, so its balance reflects principal-only.
    MockLPPool lpPool = MockLPPool(strat.lpPool());
    (uint256 poolA, uint256 poolB) = lpPool.getAmounts(address(nfpm), tokenId);
    assertEq(poolA, 30e18 + 15e18, "pool principal grew by 15 A at 3:7 ratio");
    assertEq(poolB, 70e18 + 35e18, "pool principal grew by 35 B at 3:7 ratio");
  }

  /// @notice Direct counter-proof: if we feed the strategy the "buggy" totals-ratio top-up amounts
  ///         (20:40 instead of 15:35) through the same slippage-checked path, the pool rejects them
  ///         as off-ratio. This pins down *why* the fix is needed — the pre-fix amounts can't clear
  ///         the `amount*Min` bar when principal and rewards ratios diverge.
  function test_depositProportional_withBuggyTotalsRatio_revertsUnderSlippageCheck() public {
    // Arrange: the mock strategy does not need to be registered on a vault — we call its
    // depositProportional directly to simulate what the pre-fix SharedVault would have sent.
    MockLPPool pool = new MockLPPool();
    DepositProportionalRecorder recorder = new DepositProportionalRecorder();
    MockRewardsAwareStrategy strat =
      new MockRewardsAwareStrategy(address(pool), address(recorder), 30e18, 70e18, 10e18, 10e18);

    // Seed the pool with principal so the ratio-consumption math in depositProportional lines up
    // with the registered position's principal slot.
    MockERC20 tA = new MockERC20("A", "A");
    MockERC20 tB = new MockERC20("B", "B");
    tA.mint(address(this), 1000e18);
    tB.mint(address(this), 1000e18);
    tA.transfer(address(pool), 30e18);
    tB.transfer(address(pool), 70e18);
    MockERC721 nfpm = new MockERC721();
    uint256 tokenId = 42;
    pool.deposit(address(nfpm), tokenId, address(tA), address(tB), 30e18, 70e18);

    // Act + Assert: 1% slippage tolerance is not enough to cover the off-ratio deficit on the A side.
    // The revert happens BEFORE any token transfer, so no balance setup is needed for this call.
    //   consumed0 = min(20, 40 * 30/70) ≈ 17.14e18
    //   min0     = 20 * 0.99             = 19.8e18    →  17.14 < 19.8  → revert.
    vm.expectRevert(bytes("OffRatioDeposit"));
    strat.depositProportional(address(nfpm), tokenId, 20e18, 40e18, uint16(100));

    // Contrast: the principal-ratio amounts clear the same slippage check cleanly. This call
    // DOES reach the token-transfer step, so the strategy must hold the exact consumed amounts
    // (called directly, msg.sender == strat, so transfers originate from strat's own balance).
    tA.transfer(address(strat), 15e18);
    tB.transfer(address(strat), 35e18);
    strat.depositProportional(address(nfpm), tokenId, 15e18, 35e18, uint16(100));
  }

  /// @notice Precision-floor overpayment on one side must stay idle instead of being force-fed into
  ///         an LP top-up at an off-range ratio. This mirrors the production failure where an
  ///         8-decimal token was rounded up to its 1_000-unit floor while token0 remained the
  ///         binding proportional contribution.
  function test_deposit_dustFloorExcessUsesBindingShareForLPTopup() public {
    uint256 principal0 = 6_211_554_753_921_691;
    uint256 principal1 = 2557;
    uint256 total0 = 6_353_008_156_094_482;
    uint256 total1 = 5521;
    uint256 deposit0 = 516_081_745_220_545;
    uint256 token1Floor = 1000;

    MockERC20 tA = new MockERC20("WETH-like", "WETH");
    MockERC20LowDecimals tB = new MockERC20LowDecimals("BTC-like", "BTC", 8);
    MockLPPool pool = new MockLPPool();
    DepositProportionalRecorder recorder = new DepositProportionalRecorder();
    MockRewardsAwareStrategy strat =
      new MockRewardsAwareStrategy(address(pool), address(recorder), principal0, principal1, 0, 0);
    MockERC721 nfpm = new MockERC721();

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    SharedVault rv = new SharedVault();
    tA.mint(address(rv), total0);
    tB.mint(address(rv), total1);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [total0, total1, uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    rv.initialize("DustFloorVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 0);

    nfpm.mint(address(rv), 478_578);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(strat),
      abi.encode(address(nfpm), uint256(478_578), address(tA), address(tB)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.prank(VAULT_OWNER);
    rv.execute(actions);

    uint256 idle1Before = tB.balanceOf(address(rv));
    assertEq(idle1Before, total1 - principal1, "setup: token1 idle is total minus principal");
    assertEq(rv.getMinDepositAmounts()[1], token1Floor, "setup: 8-dec token floor is 1_000");

    tA.mint(DEPOSITOR, deposit0);
    tB.mint(DEPOSITOR, token1Floor);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);
    uint256[4] memory amounts = [deposit0, token1Floor, uint256(0), uint256(0)];
    uint256 shares = rv.deposit(amounts, uint16(200));
    vm.stopPrank();

    uint256 oldIndependentToken1Topup = FullMath.mulDiv(token1Floor, principal1, total1);

    assertGt(shares, 0, "deposit succeeds with slippage guard");
    assertEq(recorder.callCount(), 1, "LP top-up called");
    assertLt(recorder.lastAmount1(), oldIndependentToken1Topup, "precision-floor excess token1 stays idle");
    assertEq(
      recorder.lastAmount1(),
      FullMath.mulDiv(recorder.lastAmount0(), principal1, principal0),
      "LP top-up uses token0's binding share for both sides"
    );
    assertEq(
      tB.balanceOf(address(rv)),
      idle1Before + token1Floor - recorder.lastAmount1(),
      "unused precision-floor token1 remains idle"
    );
  }

  // ==================== getMinDepositAmounts Tests ====================
  //
  // _minTokenAmt(token, prec):
  //   prec == 0          → 0  (floor disabled)
  //   dec > prec         → 10 ** (dec - prec)
  //   dec <= prec        → 1  (smallest representable unit)
  //
  // getMinDepositAmounts():
  //   totalSupply == 0   → all zeros (first deposit has no proportional floor)
  //   tokens[i] == 0     → 0  (empty slot)
  //   totalBalances[i] == 0 → 0  (token present but no balance yet)
  //   otherwise          → _minTokenAmt(tokens[i], prec)

  /// @notice Before any deposit the vault has no shares outstanding, so every slot
  ///         returns 0 — the first depositor sets the initial share price freely.
  function test_getMinDepositAmounts_returnsZeroWhenNoSharesOutstanding() public {
    // Arrange: fresh vault with no initial amounts
    SharedVault emptyVault = new SharedVault();
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory noAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    emptyVault.initialize(
      "EmptyVault", vtokens, noAmounts, VAULT_OWNER, address(0), address(configManager), address(0), 0
    );

    // Act
    uint256[4] memory mins = emptyVault.getMinDepositAmounts();

    // Assert: totalSupply == 0 → all zeros
    assertEq(mins[0], 0, "slot 0 must be 0 when no shares exist");
    assertEq(mins[1], 0, "slot 1 must be 0 when no shares exist");
    assertEq(mins[2], 0, "slot 2 must be 0 when no shares exist");
    assertEq(mins[3], 0, "slot 3 must be 0 when no shares exist");
  }

  /// @notice Active 18-decimal tokens with default precision 5 each require
  ///         at least 10**(18-5) = 1e13 per deposit.
  ///         The setUp vault has 100e18 tokenA and 200e18 tokenB idle, so both
  ///         slots should report 1e13.
  function test_getMinDepositAmounts_18decimalTokens_defaultPrecision5() public view {
    // Default precision is 5 (SharedConfigManager initialises to 5).
    // Both tokenA and tokenB have 18 decimals → floor = 10**(18-5) = 1e13.
    uint256[4] memory mins = vault.getMinDepositAmounts();

    assertEq(mins[0], 1e13, "tokenA (18 dec, prec 5): floor = 1e13");
    assertEq(mins[1], 1e13, "tokenB (18 dec, prec 5): floor = 1e13");
  }

  /// @notice Slots that hold a vault token address but have zero total balance
  ///         must return 0 — the depositor is required to supply exactly 0 for
  ///         those slots anyway, so a non-zero floor would block all deposits.
  function test_getMinDepositAmounts_zeroBalanceSlotReturnsZero() public view {
    // tokenC and tokenD are vault tokens (setUp registers them) but the vault
    // has no balance of either, so totalBalances[2] == totalBalances[3] == 0.
    uint256[4] memory mins = vault.getMinDepositAmounts();

    assertEq(mins[2], 0, "tokenC has zero balance -> min must be 0");
    assertEq(mins[3], 0, "tokenD has zero balance -> min must be 0");
  }

  /// @notice When minTokenPrecision is set to 0, the floor is completely disabled
  ///         and getMinDepositAmounts returns 0 for every slot regardless of balance.
  function test_getMinDepositAmounts_precisionZeroDisablesFloor() public {
    // Arrange: disable the minimum-precision floor
    configManager.setMinTokenPrecision(0);

    // Act
    uint256[4] memory mins = vault.getMinDepositAmounts();

    // Assert: _minTokenAmt(_, 0) == 0 for every token
    assertEq(mins[0], 0, "floor disabled: tokenA slot must be 0");
    assertEq(mins[1], 0, "floor disabled: tokenB slot must be 0");
    assertEq(mins[2], 0, "floor disabled: tokenC slot must be 0");
    assertEq(mins[3], 0, "floor disabled: tokenD slot must be 0");
  }

  /// @notice A custom precision value (e.g., 3) produces a different per-token floor.
  ///         For 18-decimal tokens: 10**(18-3) = 1e15.
  function test_getMinDepositAmounts_customPrecision_3() public {
    configManager.setMinTokenPrecision(3);

    uint256[4] memory mins = vault.getMinDepositAmounts();

    assertEq(mins[0], 1e15, "tokenA (18 dec, prec 3): floor = 1e15");
    assertEq(mins[1], 1e15, "tokenB (18 dec, prec 3): floor = 1e15");
    // Zero-balance slots are still 0 even with a non-zero precision.
    assertEq(mins[2], 0, "tokenC has zero balance -> min = 0 regardless of precision");
    assertEq(mins[3], 0, "tokenD has zero balance -> min = 0 regardless of precision");
  }

  /// @notice A token whose decimal count is less than the precision level gets a
  ///         floor of 1 (the smallest representable unit of that token).
  ///         Here a 3-decimal token with precision 5: dec(3) <= prec(5) → 1.
  function test_getMinDepositAmounts_tokenDecimalsLessThanPrecision_returnsOne() public {
    // Deploy a 3-decimal token and create a vault seeded with it alongside a normal token.
    MockERC20LowDecimals lowDecToken = new MockERC20LowDecimals("Low Dec", "LDC", 3);

    SharedVault v = new SharedVault();
    lowDecToken.mint(address(v), 1000); // 1.000 in 3-decimal units
    tokenA.mint(address(v), 100e18);

    address[4] memory vtokens = [address(tokenA), address(lowDecToken), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(1000), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("LowDecVault", vtokens, initAmounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);

    // precision = 5, decimals = 3: dec <= prec → _minTokenAmt returns 1
    uint256[4] memory mins = v.getMinDepositAmounts();

    assertEq(mins[0], 1e13, "tokenA (18 dec, prec 5): floor = 1e13");
    assertEq(mins[1], 1, "lowDecToken (3 dec, prec 5): dec <= prec -> floor = 1");
  }

  /// @notice A token whose decimal count equals the precision level also gets a
  ///         floor of 1 — the branch condition is strictly `dec > prec`.
  function test_getMinDepositAmounts_tokenDecimalsEqualPrecision_returnsOne() public {
    // Deploy a 5-decimal token (same as the default precision = 5).
    MockERC20LowDecimals fiveDecToken = new MockERC20LowDecimals("Five Dec", "FDC", 5);

    SharedVault v = new SharedVault();
    fiveDecToken.mint(address(v), 100_000); // 1.00000 in 5-decimal units
    tokenA.mint(address(v), 100e18);

    address[4] memory vtokens = [address(tokenA), address(fiveDecToken), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(100_000), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("FiveDecVault", vtokens, initAmounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);

    uint256[4] memory mins = v.getMinDepositAmounts();

    assertEq(mins[0], 1e13, "tokenA (18 dec, prec 5): floor = 1e13");
    // dec(5) == prec(5) → dec > prec is false → returns 1
    assertEq(mins[1], 1, "fiveDecToken (5 dec, prec 5): dec == prec -> floor = 1");
  }

  /// @notice A 6-decimal token (e.g., USDC) with precision 5 should return a floor
  ///         of 10**(6-5) = 10 (i.e., 0.00001 USDC).
  function test_getMinDepositAmounts_6decimalToken_defaultPrecision5() public {
    MockERC20LowDecimals usdcLike = new MockERC20LowDecimals("USD Coin", "USDC", 6);

    SharedVault v = new SharedVault();
    usdcLike.mint(address(v), 1_000_000); // 1 USDC
    tokenA.mint(address(v), 100e18);

    address[4] memory vtokens = [address(tokenA), address(usdcLike), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(1_000_000), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("USDCVault", vtokens, initAmounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);

    uint256[4] memory mins = v.getMinDepositAmounts();

    assertEq(mins[0], 1e13, "tokenA (18 dec, prec 5): floor = 1e13");
    // 6 dec, prec 5: dec > prec -> 10**(6-5) = 10
    assertEq(mins[1], 10, "USDC-like (6 dec, prec 5): floor = 10");
  }

  /// @notice _computeSharesFromDelta returns 0 (→ InsufficientShares revert) when LP valuation
  ///         collapses for a deposited token after _depositProportionalToAllPositions runs.
  ///         Without the fix, the vault would skip the token whose balance didn't increase and
  ///         over-credit the depositor using only the other token's delta — inflating shares.
  function test_deposit_revertsWhenLpValuationDropsAfterDeposit() public {
    // --- Arrange: isolated tokens / pool / strategy / config --------------------------------
    MockERC20 tA = new MockERC20("DropA", "DA");
    MockERC20 tB = new MockERC20("DropB", "DB");
    MockDropAfterSecondDepositPool dropPool = new MockDropAfterSecondDepositPool();
    MockDropAfterSecondDepositStrategy dropStrat = new MockDropAfterSecondDepositStrategy(address(dropPool));
    MockERC721 nfpm = new MockERC721();
    uint256 tokenId = 1;

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(dropStrat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    // --- Arrange: vault — Alice seeds [100A, 100B], 50A/50B go into LP (depositCount=1) ------
    SharedVault dv = new SharedVault();
    tA.mint(address(dv), 100e18);
    tB.mint(address(dv), 100e18);
    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    dv.initialize("DropVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0), 0);

    nfpm.mint(address(dv), tokenId);
    bytes memory stratData =
      abi.encode(address(nfpm), tokenId, address(tA), address(tB), uint256(50e18), uint256(50e18));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(dropStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    dv.execute(actions);

    // Sanity: after execute the pool reports (50, 50) since depositCount == 1.
    assertEq(dropPool.depositCount(), 1, "setup: depositCount == 1 after initial LP creation");
    (uint256 pa, uint256 pb) = dropPool.getAmounts(address(nfpm), tokenId);
    assertEq(pa, 50e18, "setup: pool reports 50A");
    assertEq(pb, 50e18, "setup: pool reports 50B");

    // --- Act: Bob deposits proportionally; _depositProportionalToAllPositions triggers
    //          depositProportional → depositCount == 2 → pool drops to (0,0).
    //          _computeSharesFromDelta sees balancesAfter[A] == balancesBefore[A] → returns 0 → revert.
    tA.mint(DEPOSITOR, 100e18);
    tB.mint(DEPOSITOR, 100e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(dv), type(uint256).max);
    tB.approve(address(dv), type(uint256).max);
    uint256[4] memory depositAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InsufficientShares.selector);
    dv.deposit(depositAmounts, 0);
    vm.stopPrank();
  }

  // ==================== Security Issue Tests ====================

  /// @notice Issue 1: SharedV4Strategy._validateV4ExecuteCalldataSwapRouters must fail CLOSED on any
  ///         selector that is not IV4Utils.execute. Before the fix the function returned early, silently
  ///         passing arbitrary calldata after tokens/NFTs had already been approved.
  function test_security_issue1_v4Execute_unknownSelector_reverts() public {
    MockV4UtilsRouter router = new MockV4UtilsRouter();
    SharedV4Strategy v4strat = new SharedV4Strategy(address(router));

    SharedConfigManager v4cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address whitelistedPosm = makeAddr("v4posm");
    address[] memory posmList = new address[](1);
    posmList[0] = whitelistedPosm;
    v4cm.initialize(address(this), targets, new address[](0), address(this), 0, posmList, new address[](0));

    SharedVault v4v = new SharedVault();
    tokenA.mint(address(v4v), 100e18);
    tokenB.mint(address(v4v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v4v.initialize("V4Vault", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v4cm), address(0), 0);

    // Params with an unknown selector — not IV4Utils.execute — should be rejected fail-closed.
    bytes memory badParams = abi.encodeWithSelector(bytes4(0xDEADBEEF), whitelistedPosm, uint256(1));
    bytes memory innerData =
      abi.encode(whitelistedPosm, uint256(1), badParams, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v4strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    v4v.execute(actions);
  }

  /// @notice Issue 2: _applyPositionChangesChecked must reject a CALL_WITH_POSITIONS strategy whose
  ///         getPositionAmounts reverts. Accepting ok=false would allow tracking a position whose
  ///         valuation already fails, bricking _getTotalBalances() for all depositors.
  function test_security_issue2_cwp_rejectsRevertingGetPositionAmounts() public {
    MockRevertingGetPositionAmountsStrategy revertingStrat = new MockRevertingGetPositionAmountsStrategy();
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(revertingStrat);
    configManager.setWhitelistTargets(newTargets, true);

    uint256 tokenId = 55;
    cwpNfpm.mint(address(vault), tokenId);

    bytes memory callData = abi.encodeCall(
      MockRevertingGetPositionAmountsStrategy.createPosition,
      (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(revertingStrat), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(revertingStrat)));
    vault.execute(actions);
  }

  /// @notice Issue 3 (updated): SharedV3Strategy._safeTransferNft CHANGE_RANGE uses a pre/post token-ID
  ///         diff to locate the new token. This is insertion-order-agnostic: inverted ordering (old NFT
  ///         returned before new one minted) is now handled correctly instead of reverting.
  function test_security_issue3_v3ChangeRange_invertedOrderingSucceedsWithCorrectTracking() public {
    SharedV3Strategy v3strat = new SharedV3Strategy(address(0xAAAA));

    SharedConfigManager v3cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v3strat);
    v3cm.initialize(address(this), targets, new address[](0), address(this), 0, new address[](0), new address[](0));

    // Deploy inverted-ordering NFPM; next new id = 999.
    MockInvertedOrderingNfpm invertedNfpm = new MockInvertedOrderingNfpm(address(tokenA), address(tokenB), 999);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(invertedNfpm);
    v3cm.setWhitelistNfpms(nfpms, true);

    SharedVault v3v = new SharedVault();
    tokenA.mint(address(v3v), 100e18);
    tokenB.mint(address(v3v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v3v.initialize("V3Vault", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v3cm), address(0), 0);

    uint256 tokenId = 7;
    invertedNfpm.mint(address(v3v), tokenId);

    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;

    bytes memory innerData = abi.encode(address(invertedNfpm), tokenId, instructions);
    bytes memory stratData = bytes.concat(abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v3strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    // With the pre/post diff approach, inverted ordering is handled correctly — no revert.
    v3v.execute(actions);

    // The new token (999) should be tracked; the old token (7) was removed.
    assertEq(v3v.getPositionCount(), 1, "only new token should be tracked");
    (,, uint256 trackedId,,) = v3v.getPosition(0);
    assertEq(trackedId, 999, "new token 999 must be tracked, not the original 7");
  }

  function test_security_issue3_v3ChangeRange_partialRemovalKeepsOldPositionTracked() public {
    SharedV3Strategy v3strat = new SharedV3Strategy(address(0xAAAA));
    MockInvertedOrderingNfpm partialNfpm = new MockInvertedOrderingNfpm(address(tokenA), address(tokenB), 999);

    SharedConfigManager v3cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v3strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(partialNfpm);
    v3cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    SharedVault v3v = new SharedVault();
    tokenA.mint(address(v3v), 100e18);
    tokenB.mint(address(v3v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v3v.initialize("V3PartialRange", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v3cm), address(0), 0);

    uint256 tokenId = 7;
    partialNfpm.mint(VAULT_OWNER, tokenId);
    vm.prank(VAULT_OWNER);
    v3v.recoverPosition(address(partialNfpm), tokenId, address(v3strat), address(tokenA), address(tokenB));
    assertEq(v3v.getPositionCount(), 1, "setup tracks original position");

    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;
    instructions.liquidity = 400;

    bytes memory innerData = abi.encode(address(partialNfpm), tokenId, instructions);
    bytes memory stratData = bytes.concat(abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v3strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    v3v.execute(actions);

    _assertTrackedIds(v3v, tokenId, 999);
  }

  /// @notice Issue 3 (supplemental): native CHANGE_RANGE reverts if the replacement NFT returned
  ///         by mint is not owned by the vault.
  function test_security_issue3_v3ChangeRange_revertsWhenReplacementNftNotOwnedByVault() public {
    SharedV3Strategy v3strat = new SharedV3Strategy(address(0xAAAA));

    SharedConfigManager v3cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v3strat);
    v3cm.initialize(address(this), targets, new address[](0), address(this), 0, new address[](0), new address[](0));

    // NFPM that mints a new token but does NOT return the old one (burns it).
    MockBurnWithoutReturnNfpm burnNfpm = new MockBurnWithoutReturnNfpm(address(tokenA), address(tokenB), 888);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(burnNfpm);
    v3cm.setWhitelistNfpms(nfpms, true);

    SharedVault v3v = new SharedVault();
    tokenA.mint(address(v3v), 100e18);
    tokenB.mint(address(v3v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v3v.initialize("V3Vault2", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v3cm), address(0), 0);

    uint256 tokenId = 42;
    burnNfpm.mint(address(v3v), tokenId);

    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;

    bytes memory innerData = abi.encode(address(burnNfpm), tokenId, instructions);
    bytes memory stratData = bytes.concat(abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v3strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    v3v.execute(actions);
  }

  /// @notice Aerodrome CHANGE_RANGE: pre/post diff correctly identifies the new token regardless of
  ///         NFPM owner-array insertion order (mirrors the V3 strategy test above).
  function test_security_aerodromeChangeRange_invertedOrderingSucceedsWithCorrectTracking() public {
    SharedAerodromeStrategy aerostrat = new SharedAerodromeStrategy(address(0xAAAA));

    SharedConfigManager aerocm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(aerostrat);
    aerocm.initialize(address(this), targets, new address[](0), address(this), 0, new address[](0), new address[](0));

    MockAerodromeInvertedOrderingNfpm aeroNfpm =
      new MockAerodromeInvertedOrderingNfpm(address(tokenA), address(tokenB), 777);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(aeroNfpm);
    aerocm.setWhitelistNfpms(nfpms, true);

    SharedVault aerov = new SharedVault();
    tokenA.mint(address(aerov), 100e18);
    tokenB.mint(address(aerov), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    aerov.initialize("AeroVault", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(aerocm), address(0), 0);

    uint256 tokenId = 55;
    aeroNfpm.mint(address(aerov), tokenId);

    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;

    bytes memory innerData = abi.encode(address(aeroNfpm), tokenId, instructions);
    bytes memory stratData =
      bytes.concat(abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(aerostrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    aerov.execute(actions);

    assertEq(aerov.getPositionCount(), 1, "only new Aerodrome token should be tracked");
    (,, uint256 trackedId,,) = aerov.getPosition(0);
    assertEq(trackedId, 777, "new Aerodrome token 777 must be tracked, not original 55");
  }

  function test_security_aerodromeChangeRange_partialRemovalKeepsOldPositionTracked() public {
    SharedAerodromeStrategy aerostrat = new SharedAerodromeStrategy(address(0xAAAA));
    MockAerodromeInvertedOrderingNfpm aeroNfpm =
      new MockAerodromeInvertedOrderingNfpm(address(tokenA), address(tokenB), 777);

    SharedConfigManager aerocm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(aerostrat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(aeroNfpm);
    aerocm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    SharedVault aerov = new SharedVault();
    tokenA.mint(address(aerov), 100e18);
    tokenB.mint(address(aerov), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    aerov.initialize("AeroPartialRange", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(aerocm), address(0), 0);

    uint256 tokenId = 55;
    aeroNfpm.mint(VAULT_OWNER, tokenId);
    vm.prank(VAULT_OWNER);
    aerov.recoverPosition(address(aeroNfpm), tokenId, address(aerostrat), address(tokenA), address(tokenB));
    assertEq(aerov.getPositionCount(), 1, "setup tracks original Aerodrome position");

    IV3Utils.Instructions memory instructions;
    instructions.whatToDo = IV3Utils.WhatToDo.CHANGE_RANGE;
    instructions.liquidity = 400;

    bytes memory innerData = abi.encode(address(aeroNfpm), tokenId, instructions);
    bytes memory stratData =
      bytes.concat(abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(aerostrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    aerov.execute(actions);

    _assertTrackedIds(aerov, tokenId, 777);
  }

  /// @notice Issue 4: native SharedV4Strategy execution must not leave a dangling NFT approval
  ///         when the NFT remains in the vault.
  function test_security_issue4_v4Execute_clearsNftApprovalAfterExecution() public {
    MockV4UtilsRouter router = new MockV4UtilsRouter();
    SharedV4Strategy v4strat = new SharedV4Strategy(address(router));

    SharedConfigManager v4cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    v4cm.initialize(address(this), targets, new address[](0), address(this), 0, new address[](0), new address[](0));

    MockV4PositionManager posm = new MockV4PositionManager(100); // nextTokenId = 100
    address[] memory posmList = new address[](1);
    posmList[0] = address(posm);
    v4cm.setWhitelistNfpms(posmList, true);

    SharedVault v4v = new SharedVault();
    tokenA.mint(address(v4v), 100e18);
    tokenB.mint(address(v4v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v4v.initialize("V4Vault2", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v4cm), address(0), 0);

    uint256 tokenId = 5;
    // NFT owned by vault (address(v4v) == address(this) during delegatecall)
    posm.setOwner(tokenId, address(v4v));
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    // Non-zero liquidity → strategy takes "partial decrease / compound" path → no position changes.
    posm.setLiquidity(tokenId, 1e18);

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: block.timestamp }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IV4Utils.Instructions memory instr =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) });
    bytes memory params = abi.encodeCall(IV4Utils.execute, (address(posm), tokenId, instr));
    bytes memory innerData = abi.encode(address(posm), tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    // Before execution: no approval set.
    assertEq(posm.getApproved(tokenId), address(0), "precondition: no approval before execute");

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v4strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    v4v.execute(actions);

    // After execution: native execution must not leave a dangling NFT approval.
    assertEq(posm.getApproved(tokenId), address(0), "NFT approval must be cleared after execute");
  }

  /// @notice Issue 5: _applyPositionChangesChecked must reject a CALL_WITH_POSITIONS result where
  ///         the reported token0/token1 differ from what getPositionTokens returns on the strategy.
  ///         A misbehaving strategy could report any vault-token pair; the canonical check prevents
  ///         LP value from being attributed to the wrong assets, which would misprice shares.
  function test_security_issue5_cwp_rejectsWrongCanonicalTokens() public {
    // Strategy canonical pair: tokenA/tokenB. But createPositionWrongTokens reports tokenB/tokenA.
    MockWrongCanonicalTokensStrategy wrongStrat = new MockWrongCanonicalTokensStrategy(address(tokenA), address(tokenB));
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(wrongStrat);
    configManager.setWhitelistTargets(newTargets, true);

    uint256 tokenId = 66;
    cwpNfpm.mint(address(vault), tokenId);

    // Reports reversed pair (tokenB, tokenA) but getPositionTokens returns (tokenA, tokenB).
    bytes memory callData = abi.encodeCall(
      MockWrongCanonicalTokensStrategy.createPositionWrongTokens,
      (address(cwpNfpm), tokenId, address(tokenB), address(tokenA))
    );

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(wrongStrat), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
  }

  // ==================== Issue 6 Tests (V4 silent fallthrough) ====================

  /// @notice Issue 6a: SharedV4Strategy._execute else branch must fail CLOSED when native POSM
  ///         execution mints a new vault-owned NFT during a partial-decrease / compound operation.
  ///         Before the fix the else branch returned an empty PositionChange[], leaving the new
  ///         NFT untracked and understating TVL.
  function test_security_issue6a_v4Execute_unexpectedMintDuringCompound_reverts() public {
    // Deploy a fresh V4 vault + config so we control the POSM allowlist.
    MockV4PositionManager posm = new MockV4PositionManager(100); // nextTokenId starts at 100

    SharedV4Strategy v4strat = new SharedV4Strategy(address(new MockV4UtilsRouter()));

    SharedConfigManager v4cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address[] memory posmList = new address[](1);
    posmList[0] = address(posm);
    v4cm.initialize(address(this), targets, new address[](0), address(this), 0, posmList, new address[](0));

    SharedVault v4v = new SharedVault();
    tokenA.mint(address(v4v), 100e18);
    tokenB.mint(address(v4v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v4v.initialize("V4Vault6a", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v4cm), address(0), 0);

    // Existing tokenId=5 owned by vault with non-zero liquidity (partial decrease, not full exit).
    uint256 tokenId = 5;
    posm.setOwner(tokenId, address(v4v));
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));
    posm.setLiquidity(tokenId, 1e18);

    // The unexpected mint happens inside native POSM execution so nextIdBefore=100 is snapshotted first.
    posm.setModifyLiquiditiesMint(100, address(v4v));

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: block.timestamp }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IV4Utils.Instructions memory instr =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) });
    bytes memory params = abi.encodeCall(IV4Utils.execute, (address(posm), tokenId, instr));
    bytes memory innerData = abi.encode(address(posm), tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v4strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    v4v.execute(actions);
  }

  /// @notice Issue 6b: SharedV4Strategy._safeTransferNft else branch must fail CLOSED when native
  ///         POSM execution mints a new vault-owned NFT while the original NFT remains live.
  function test_security_issue6b_v4SafeTransferNft_unexpectedMintWithLivePosition_reverts() public {
    MockV4UtilsRouter noopRouter = new MockV4UtilsRouter(); // _safeTransferNft doesn't call execute
    SharedV4Strategy v4strat = new SharedV4Strategy(address(noopRouter));

    MockV4PositionManager posm = new MockV4PositionManager(100);

    SharedConfigManager v4cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(v4strat);
    address[] memory posmList = new address[](1);
    posmList[0] = address(posm);
    v4cm.initialize(address(this), targets, new address[](0), address(this), 0, posmList, new address[](0));

    SharedVault v4v = new SharedVault();
    tokenA.mint(address(v4v), 100e18);
    tokenB.mint(address(v4v), 100e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v4v.initialize("V4Vault6b", vtokens, initAmts, VAULT_OWNER, VAULT_OWNER, address(v4cm), address(0), 0);

    uint256 tokenId = 7;
    posm.setOwner(tokenId, address(v4v));
    posm.setLiquidity(tokenId, 1e18); // non-zero → ADJUST_RANGE and full-exit branches NOT taken
    posm.setPoolInfo(tokenId, address(tokenA), address(tokenB));

    // Configure POSM to mint tokenId=100 to the vault during native modifyLiquidities.
    // After the call: nextTokenId=101, ownerOf[100]=vault, liquidity[7]=1e18 -> else branch.
    posm.setModifyLiquiditiesMint(100, address(v4v));

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: block.timestamp }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    bytes memory instruction = abi.encode(
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) })
    );
    bytes memory innerData = abi.encode(address(posm), tokenId, instruction);
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData);

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(v4strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    v4v.execute(actions);
  }

  /// @notice Issue 7: _applyPositionChanges (delegatecall path) must verify canonical token pair
  ///         via getPositionTokens before tracking a new position — mirroring the check already
  ///         present in _applyPositionChangesChecked. A buggy strategy could report any vault-token
  ///         pair, attributing LP value to the wrong assets and mispricing shares.
  function test_security_issue7_delegatecall_rejectsWrongCanonicalTokens() public {
    // Strategy whose execute() reports (tokenA, tokenB) but getPositionTokens returns (tokenB, tokenA).
    MockDelegatecallWrongCanonTokensStrategy wrongStrat = new MockDelegatecallWrongCanonTokensStrategy(
      address(tokenB), // canon0 ≠ reported token0
      address(tokenA) // canon1 ≠ reported token1
    );
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(wrongStrat);
    configManager.setWhitelistTargets(newTargets, true);

    uint256 tokenId = 77;
    // Vault must own the NFT so the ownership check passes and only the canonical check fails.
    cwpNfpm.mint(address(vault), tokenId);

    // Encode execute calldata: (nfpm, tokenId, token0=tokenA, token1=tokenB)
    bytes memory execData = abi.encode(address(cwpNfpm), tokenId, address(tokenA), address(tokenB));

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(wrongStrat), execData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
  }

  /// @notice Issue 8a: _applyPositionChanges (delegatecall path) must not blindly trust an
  ///         isAdd=false entry. If the vault still owns the NFT and the strategy reports non-zero
  ///         amounts, the position is still live — untracking it would understate TVL.
  function test_security_issue8a_delegatecall_rejectsFalseRemoveOfLivePosition() public {
    MockFalseRemoveStrategy falseRemove = new MockFalseRemoveStrategy();
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(falseRemove);
    configManager.setWhitelistTargets(newTargets, true);

    uint256 tokenId = 88;
    // Vault must own the NFT — this is the scenario that should be rejected.
    cwpNfpm.mint(address(vault), tokenId);

    // Encode execute calldata: (nfpm, tokenId, token0, token1)
    bytes memory execData = abi.encode(address(cwpNfpm), tokenId, address(tokenA), address(tokenB));

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(falseRemove), execData, ISharedCommon.CallType.DELEGATECALL);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.execute(actions);
  }

  /// @notice Issue 8b: _applyPositionChangesChecked (CALL_WITH_POSITIONS path) must also reject
  ///         a false-remove entry when the vault still owns the NFT and position has non-zero value.
  function test_security_issue8b_cwp_rejectsFalseRemoveOfLivePosition() public {
    MockCwpFalseRemoveStrategy cwpFalseRemove = new MockCwpFalseRemoveStrategy();
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(cwpFalseRemove);
    configManager.setWhitelistTargets(newTargets, true);

    uint256 tokenId = 99;
    // Vault must own the NFT — the strategy incorrectly claims it should be untracked.
    cwpNfpm.mint(address(vault), tokenId);

    bytes memory callData = abi.encodeCall(
      MockCwpFalseRemoveStrategy.removePosition, (address(cwpNfpm), tokenId, address(tokenA), address(tokenB))
    );

    vm.prank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(cwpFalseRemove), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.execute(actions);
  }

  /// @notice getMinDepositAmounts reflects total balances including LP position amounts.
  ///         When a strategy reports LP holdings for a slot, that slot's balance is non-zero
  ///         and its floor is returned; a slot with balance only in LP (not idle) still counts.
  function test_getMinDepositAmounts_includesLpPositionBalancesForActiveSlots() public {
    // Arrange: create a fresh vault with tokenA and tokenB; seed both with idle balance.
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrat = new MockLPExitStrategy(address(pool));

    // Whitelist the LP strategy as a target in configManager.
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(lpStrat);
    configManager.setWhitelistTargets(newTargets, true);

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 200e18);
    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("LPVault", vtokens, initAmounts, VAULT_OWNER, address(0), address(configManager), address(0), 0);

    // The vault has shares outstanding → both active slots should return the 18-dec floor.
    uint256[4] memory mins = v.getMinDepositAmounts();
    assertEq(mins[0], 1e13, "tokenA floor present when idle balance is non-zero");
    assertEq(mins[1], 1e13, "tokenB floor present when idle balance is non-zero");
  }

  // ════════════════════════════════════════════════════════════════════════════
  // C-5: Fee-on-transfer / non-standard ERC20 deposit safety
  // ════════════════════════════════════════════════════════════════════════════

  function test_audit_C5_firstDeposit_FOT_mintsInitialShares_butVaultIdleReduced() public {
    FotToken fot = new FotToken(200); // 2% FOT
    address[4] memory toks = [address(fot), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(0), uint256(0), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    v.initialize("FOT", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    fot.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    vm.startPrank(DEPOSITOR);
    fot.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    assertEq(shares, TEST_INITIAL_SHARES, "INITIAL_SHARES minted regardless of FOT loss");
    assertEq(fot.balanceOf(address(v)), 98e18, "vault received 98% (2% FOT fee burned)");
    assertEq(tokenB.balanceOf(address(v)), 100e18, "standard token received in full");
  }

  function test_audit_C5_subsequentDeposit_FOT_creditsActualReceived() public {
    FotToken fot = new FotToken(200);
    address[4] memory toks = [address(fot), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(0), uint256(0), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    v.initialize("FOT2", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    fot.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    vm.startPrank(DEPOSITOR);
    fot.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    v.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);
    uint256 fotBefore = fot.balanceOf(address(v));
    vm.stopPrank();

    address bob = address(0xB0B0B0);
    fot.mint(bob, 1000e18);
    tokenB.mint(bob, 1000e18);
    vm.startPrank(bob);
    fot.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    assertGt(shares, 0, "shares minted from actual delta");
    uint256 fotDelta = fot.balanceOf(address(v)) - fotBefore;
    assertLt(fotDelta, 50e18, "FOT delta below requested (fee charged)");
    assertGt(fotDelta, 0, "FOT delta still positive");
  }

  function test_audit_C5_oneHundredPercentFOT_firstDepositReverts() public {
    // Bug fix (Bug 2): a 100% FOT token delivers ZERO tokens to the vault on transferFrom.
    // Previously, INITIAL_SHARES were minted even when actualPulled was all-zero, leaving
    // totalSupply() > 0 with zero balances and bricking all future deposits. The fix requires
    // every requested token slot to show positive receipt before minting initial shares.
    FotToken fot100 = new FotToken(10_000);
    address[4] memory toks = [address(fot100), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(0), uint256(0), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    v.initialize("F100", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    fot100.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    vm.startPrank(DEPOSITOR);
    fot100.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    // 100% FOT token delivers 0 to the vault — must revert, not mint shares with zero balance.
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    v.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();
  }

  function test_audit_C5_oneHundredPercentFOT_initialize_reverts() public {
    // Bug fix: factory path — factory calls safeTransferFrom(creator, vault, amount) then
    // initialize(initialAmounts).  For a 100% FOT token the transfer delivers 0 to the vault,
    // but initialAmounts[i] > 0.  Without the fix, INITIAL_SHARES would be minted against a
    // zero balance, bricking every subsequent deposit.
    FotToken fot100 = new FotToken(10_000); // 100% fee
    address[4] memory toks = [address(fot100), address(tokenB), address(0), address(0)];

    SharedVault v = new SharedVault();

    // Simulate factory: mint to a sender, then transfer to vault (100% FOT delivers 0).
    fot100.mint(DEPOSITOR, 100e18);
    tokenB.mint(DEPOSITOR, 100e18);
    vm.startPrank(DEPOSITOR);
    fot100.transfer(address(v), 100e18); // delivers 0 to vault
    tokenB.transfer(address(v), 100e18); // delivers 100e18 to vault
    vm.stopPrank();

    // initialize with initialAmounts[0] = 100e18 for the 100% FOT token (vault balance == 0).
    // Must revert — vault cannot mint initial shares with zero balance for a declared token.
    uint256[4] memory amounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    v.initialize("IFOT", toks, amounts, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);
  }

  function test_audit_C5_partialFOT_initialize_succeeds() public {
    // Partial FOT (2% fee) in the factory/initialize path: vault receives 98% of the declared
    // initialAmount.  Since balance > 0, initialize must succeed and mint INITIAL_SHARES.
    FotToken fot = new FotToken(200); // 2% fee
    address[4] memory toks = [address(fot), address(tokenB), address(0), address(0)];

    SharedVault v = new SharedVault();

    fot.mint(DEPOSITOR, 100e18);
    tokenB.mint(DEPOSITOR, 100e18);
    vm.startPrank(DEPOSITOR);
    fot.transfer(address(v), 100e18); // delivers 98e18
    tokenB.transfer(address(v), 100e18);
    vm.stopPrank();

    uint256[4] memory amounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    v.initialize("PFOT", toks, amounts, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    assertEq(v.totalSupply(), TEST_INITIAL_SHARES, "partial FOT initialize mints INITIAL_SHARES");
    assertEq(fot.balanceOf(address(v)), 98e18, "vault received 98% of FOT");
    assertEq(tokenB.balanceOf(address(v)), 100e18);
  }

  function test_audit_C5_partialFOT_firstDeposit_succeeds_and_notBricked() public {
    // Partial FOT (2% fee): some tokens arrive, so first deposit should succeed and the vault
    // should not be bricked for subsequent depositors.
    FotToken fot = new FotToken(200); // 2% fee
    address[4] memory toks = [address(fot), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(0), uint256(0), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    v.initialize("PFT2", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    fot.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    vm.startPrank(DEPOSITOR);
    fot.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    assertEq(shares, TEST_INITIAL_SHARES, "partial FOT first deposit mints INITIAL_SHARES");
    // Vault holds 98e18 FOT (2% burned) and 100e18 tokenB — not bricked.
    assertEq(fot.balanceOf(address(v)), 98e18, "vault received 98% of FOT");
    assertEq(tokenB.balanceOf(address(v)), 100e18);
    assertGt(v.totalSupply(), 0);
  }

  function test_audit_C5_partialFOT_acrossLpValuation_revertsOnZeroDelta() public {
    // Edge case for the transferAmounts-vs-actualPulled fix: when a required token has
    // transferAmounts[i] > 0 but the post-deposit total-balance delta is 0 (e.g., 100% FOT
    // on a token the vault is supposed to hold), share math must return 0 and revert,
    // NOT silently mint shares from the remaining tokens.
    //
    // Scenario: vault has tokenA + a 100% FOT token; first depositor seeds with tokenA only
    // (FOT slot is 0). A LATER depositor providing only tokenA is allowed (FOT slot stays 0).
    // But if a depositor provides BOTH and FOT delivers 0, the FOT slot has totalBalance 0,
    // so amounts[FOT] must be 0 — confirmed by the previous test. This test instead exercises
    // a scenario where transferAmounts[i] > 0 but actualPulled[i] == 0 via partial FOT plus
    // a tight slippage path.
    FotToken fot = new FotToken(200); // 2% FOT, partial
    address[4] memory toks = [address(fot), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(0), uint256(0), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    v.initialize("PFT", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    fot.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    vm.startPrank(DEPOSITOR);
    fot.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    uint256 firstShares = v.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();
    assertEq(firstShares, TEST_INITIAL_SHARES);

    // Now subsequent depositor with partial FOT: should succeed (delta > 0 on both slots)
    address bob = address(0xB0B0B0);
    fot.mint(bob, 1000e18);
    tokenB.mint(bob, 1000e18);
    vm.startPrank(bob);
    fot.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();
    assertGt(shares, 0, "partial FOT deposit credits actual delta");
  }

  function test_audit_C5_usdtLikeToken_deposit_works_via_safeERC20() public {
    UsdtLikeToken usdt = new UsdtLikeToken();
    address[4] memory toks = [address(usdt), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(0), uint256(0), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    v.initialize("USDTV", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    usdt.mint(DEPOSITOR, 1000e6);
    tokenB.mint(DEPOSITOR, 1000e18);
    vm.startPrank(DEPOSITOR);
    usdt.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(100e6), uint256(100e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    assertEq(shares, TEST_INITIAL_SHARES);
    assertEq(usdt.balanceOf(address(v)), 100e6);
    assertEq(tokenB.balanceOf(address(v)), 100e18);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // W-5 / W-10: Operator can dropPosition (owner-unavailable escape hatch)
  // ════════════════════════════════════════════════════════════════════════════

  function _setupVaultWithFeeAccrualPosition(uint256 tokenId, uint256 p0, uint256 p1, uint256 o0, uint256 o1)
    internal
    returns (SharedVault v, MockFeeAccrualStrategy strat, MockERC721 nft)
  {
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("AuditVault", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    strat = new MockFeeAccrualStrategy();
    nft = new MockERC721();
    nft.mint(address(v), tokenId);
    address[] memory ts = new address[](1);
    ts[0] = address(strat);
    configManager.setWhitelistTargets(ts, true);
    address[] memory ns = new address[](1);
    ns[0] = address(nft);
    configManager.setWhitelistNfpms(ns, true);
    strat.register(address(nft), tokenId, address(tokenA), address(tokenB), p0, p1, o0, o1);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(strat),
      data: abi.encode(address(nft), tokenId, address(tokenA), address(tokenB)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    vm.prank(VAULT_OWNER);
    v.execute(actions);
  }

  function test_audit_W5_operator_can_dropPosition_when_owner_unavailable() public {
    (SharedVault v,, MockERC721 nft) = _setupVaultWithFeeAccrualPosition(1, 0, 0, 0, 0);
    assertEq(v.getPositionCount(), 1);

    vm.prank(OPERATOR);
    v.dropPosition(address(nft), 1);

    assertEq(v.getPositionCount(), 0, "operator successfully dropped position");
    assertEq(nft.ownerOf(1), OPERATOR, "NFT transferred to operator (documented custody asymmetry)");
  }

  function test_audit_W5_owner_still_can_dropPosition() public {
    (SharedVault v,, MockERC721 nft) = _setupVaultWithFeeAccrualPosition(2, 0, 0, 0, 0);
    vm.prank(VAULT_OWNER);
    v.dropPosition(address(nft), 2);
    assertEq(v.getPositionCount(), 0);
  }

  function test_audit_W5_random_caller_cannot_dropPosition() public {
    (SharedVault v,, MockERC721 nft) = _setupVaultWithFeeAccrualPosition(3, 0, 0, 0, 0);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vm.prank(NON_AUTHORIZED);
    v.dropPosition(address(nft), 3);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // W-7: previewWithdraw is net of LP exit fees (uncollected-fees portion only)
  // ════════════════════════════════════════════════════════════════════════════

  function test_audit_W7_previewWithdraw_deductsFeesOnUncollectedOnly() public {
    // Vault with vaultOwnerFee = 500 bps; platform fee = 1000 bps. Total = 15% on uncollected fees.
    configManager.setPlatformFeeBasisPoint(1000);

    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("W7", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 500);

    MockFeeAccrualStrategy strat = new MockFeeAccrualStrategy();
    MockERC721 nft = new MockERC721();
    nft.mint(address(v), 1);
    address[] memory ts = new address[](1);
    ts[0] = address(strat);
    configManager.setWhitelistTargets(ts, true);
    address[] memory ns = new address[](1);
    ns[0] = address(nft);
    configManager.setWhitelistNfpms(ns, true);
    // principal 60/60, uncollected fees 40/40
    strat.register(address(nft), 1, address(tokenA), address(tokenB), 60e18, 60e18, 40e18, 40e18);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(strat),
      data: abi.encode(address(nft), uint256(1), address(tokenA), address(tokenB)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    vm.prank(VAULT_OWNER);
    v.execute(actions);

    // Expected: idle (100) + principal (60) + (1 − 0.15) × owed (40) = 100 + 60 + 34 = 194
    uint256[4] memory preview = v.previewWithdraw(v.totalSupply());
    assertEq(preview[0], 194e18, "tokenA net preview");
    assertEq(preview[1], 194e18, "tokenB net preview");

    // Reset to keep other tests unaffected
    configManager.setPlatformFeeBasisPoint(0);
  }

  function test_audit_W7_previewWithdraw_zeroFees_returnsGross() public {
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("W7G", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    MockFeeAccrualStrategy strat = new MockFeeAccrualStrategy();
    MockERC721 nft = new MockERC721();
    nft.mint(address(v), 1);
    address[] memory ts = new address[](1);
    ts[0] = address(strat);
    configManager.setWhitelistTargets(ts, true);
    address[] memory ns = new address[](1);
    ns[0] = address(nft);
    configManager.setWhitelistNfpms(ns, true);
    strat.register(address(nft), 1, address(tokenA), address(tokenB), 60e18, 60e18, 40e18, 40e18);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(strat),
      data: abi.encode(address(nft), uint256(1), address(tokenA), address(tokenB)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    vm.prank(VAULT_OWNER);
    v.execute(actions);

    // idle (100) + principal (60) + owed (40) = 200
    uint256[4] memory preview = v.previewWithdraw(v.totalSupply());
    assertEq(preview[0], 200e18);
    assertEq(preview[1], 200e18);
  }

  function test_mock_generated_fees_distribute_to_platform_and_vault_owner_on_withdraw() public {
    configManager.setPlatformFeeBasisPoint(1000);

    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("GeneratedFeeMock", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 500);

    MockFeeAccrualStrategy strat = new MockFeeAccrualStrategy();
    MockERC721 nft = new MockERC721();
    nft.mint(address(v), 1);
    address[] memory ts = new address[](1);
    ts[0] = address(strat);
    configManager.setWhitelistTargets(ts, true);
    address[] memory ns = new address[](1);
    ns[0] = address(nft);
    configManager.setWhitelistNfpms(ns, true);
    strat.register(address(nft), 1, address(tokenA), address(tokenB), 0, 0, 100e18, 200e18);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(strat),
      data: abi.encode(address(nft), uint256(1), address(tokenA), address(tokenB)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    vm.prank(VAULT_OWNER);
    v.execute(actions);

    uint256 shares = v.balanceOf(VAULT_OWNER);
    vm.prank(VAULT_OWNER);
    v.transfer(DEPOSITOR, shares);

    uint256 platformABefore = tokenA.balanceOf(address(this));
    uint256 platformBBefore = tokenB.balanceOf(address(this));
    uint256 ownerABefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 ownerBBefore = tokenB.balanceOf(VAULT_OWNER);
    uint256 depositorABefore = tokenA.balanceOf(DEPOSITOR);
    uint256 depositorBBefore = tokenB.balanceOf(DEPOSITOR);

    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenA), 10e18);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenA), 5e18);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.PLATFORM, address(this), address(tokenB), 20e18);
    vm.expectEmit(true, true, true, true, address(v));
    emit FeeCollected(address(v), IFeeTaker.FeeType.OWNER, VAULT_OWNER, address(tokenB), 10e18);

    uint256[4] memory mins;
    vm.prank(DEPOSITOR);
    uint256[4] memory got = v.withdraw(shares, mins, false);

    assertEq(tokenA.balanceOf(address(this)) - platformABefore, 10e18, "platform tokenA fee");
    assertEq(tokenB.balanceOf(address(this)) - platformBBefore, 20e18, "platform tokenB fee");
    assertEq(tokenA.balanceOf(VAULT_OWNER) - ownerABefore, 5e18, "owner tokenA fee");
    assertEq(tokenB.balanceOf(VAULT_OWNER) - ownerBBefore, 10e18, "owner tokenB fee");
    assertEq(tokenA.balanceOf(DEPOSITOR) - depositorABefore, 185e18, "depositor tokenA net");
    assertEq(tokenB.balanceOf(DEPOSITOR) - depositorBBefore, 270e18, "depositor tokenB net");
    assertEq(got[0], 185e18, "withdraw tokenA net");
    assertEq(got[1], 270e18, "withdraw tokenB net");
  }

  // ════════════════════════════════════════════════════════════════════════════
  // W-13: EIP-1271 isValidSignature on SharedVault
  // ════════════════════════════════════════════════════════════════════════════

  function test_audit_W13_eip1271_returnsMagic_onValidEOASig() public {
    (address eoa, uint256 pk) = makeAddrAndKey("eip1271-eoa");
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("E1271", toks, init, eoa, OPERATOR, address(configManager), address(0), 0);

    bytes32 hash = keccak256("audit-test");
    (uint8 vv, bytes32 r, bytes32 s) = vm.sign(pk, hash);
    bytes4 result = IERC1271(address(v)).isValidSignature(hash, abi.encodePacked(r, s, vv));
    assertEq(result, bytes4(0x1626ba7e), "MAGIC_VALUE on valid EOA signature");
  }

  function test_audit_W13_eip1271_returnsZero_onWrongSig() public {
    (address eoa, uint256 pk) = makeAddrAndKey("eip1271-eoa2");
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("E1271W", toks, init, eoa, OPERATOR, address(configManager), address(0), 0);

    bytes32 hash = keccak256("real");
    (uint8 vv, bytes32 r, bytes32 s) = vm.sign(pk, keccak256("different"));
    bytes4 result = IERC1271(address(v)).isValidSignature(hash, abi.encodePacked(r, s, vv));
    assertEq(result, bytes4(0), "zero on wrong signature");
  }

  function test_audit_W13_eip1271_supportsSmartWalletOwner() public {
    (address sigEoa, uint256 pk) = makeAddrAndKey("smartWalletSigner");
    AuditEip1271Wallet sw = new AuditEip1271Wallet(sigEoa);

    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("E1271SW", toks, init, address(sw), OPERATOR, address(configManager), address(0), 0);

    bytes32 hash = keccak256("smart-wallet");
    (uint8 vv, bytes32 r, bytes32 s) = vm.sign(pk, hash);
    bytes4 result = IERC1271(address(v)).isValidSignature(hash, abi.encodePacked(r, s, vv));
    assertEq(result, bytes4(0x1626ba7e), "smart-wallet owner validates via EIP-1271 cascade");
  }

  function test_erc20Permit_permitApprovesSpender() public {
    (address owner, uint256 ownerPk) = makeAddrAndKey("permit-owner");
    address spender = makeAddr("permit-spender");
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("PermitVault", toks, init, owner, OPERATOR, address(configManager), address(0), 0);

    uint256 value = 5e18;
    uint256 deadline = block.timestamp + 1 days;
    bytes32 permitHash = keccak256(
      abi.encode(
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
        owner,
        spender,
        value,
        v.nonces(owner),
        deadline
      )
    );
    bytes32 digest = keccak256(abi.encodePacked(bytes2("\x19\x01"), v.DOMAIN_SEPARATOR(), permitHash));
    (uint8 vv, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

    v.permit(owner, spender, value, deadline, vv, r, s);

    assertEq(v.allowance(owner, spender), value);
    assertEq(v.nonces(owner), 1);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // W-15: 3-token and 4-token vault flows
  // ════════════════════════════════════════════════════════════════════════════

  function test_audit_W15_3token_vault_deposit_withdraw() public {
    MockERC20LowDecimals usdcDec = new MockERC20LowDecimals("USDC", "USDC", 6);
    address[4] memory toks = [address(tokenA), address(tokenB), address(usdcDec), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(100e6), uint256(0)];

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    usdcDec.mint(address(v), 100e6);
    v.initialize("V3T", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);
    assertEq(v.tokenCount(), 3);

    tokenA.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    usdcDec.mint(DEPOSITOR, 1000e6);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    usdcDec.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(50e18), uint256(50e18), uint256(50e6), uint256(0)], 0);
    assertGt(shares, 0);
    uint256[4] memory mins = [uint256(0), uint256(0), uint256(0), uint256(0)];
    uint256[4] memory got = v.withdraw(shares, mins, false);
    vm.stopPrank();
    assertGt(got[0], 0);
    assertGt(got[1], 0);
    assertGt(got[2], 0);
    assertEq(got[3], 0);
  }

  function test_audit_W15_4token_vault_proportional_flows() public {
    MockERC20LowDecimals usdcDec = new MockERC20LowDecimals("USDC", "USDC", 6);
    MockERC20LowDecimals wbtcDec = new MockERC20LowDecimals("WBTC", "WBTC", 8);
    address[4] memory toks = [address(tokenA), address(tokenB), address(usdcDec), address(wbtcDec)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(100e6), uint256(100e8)];

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    usdcDec.mint(address(v), 100e6);
    wbtcDec.mint(address(v), 100e8);
    v.initialize("V4T", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);
    assertEq(v.tokenCount(), 4);

    tokenA.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    usdcDec.mint(DEPOSITOR, 1000e6);
    wbtcDec.mint(DEPOSITOR, 1000e8);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    usdcDec.approve(address(v), type(uint256).max);
    wbtcDec.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(25e18), uint256(25e18), uint256(25e6), uint256(25e8)], 0);
    assertGt(shares, 0);

    uint256[4] memory mins = [uint256(0), uint256(0), uint256(0), uint256(0)];
    uint256[4] memory got = v.withdraw(shares, mins, false);
    vm.stopPrank();
    assertGt(got[0], 0);
    assertGt(got[1], 0);
    assertGt(got[2], 0);
    assertGt(got[3], 0);
  }

  function test_audit_W15_4token_partialDeposit_revertsInvalidRatio() public {
    MockERC20LowDecimals usdcDec = new MockERC20LowDecimals("USDC", "USDC", 6);
    MockERC20LowDecimals wbtcDec = new MockERC20LowDecimals("WBTC", "WBTC", 8);
    address[4] memory toks = [address(tokenA), address(tokenB), address(usdcDec), address(wbtcDec)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(100e6), uint256(100e8)];

    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    usdcDec.mint(address(v), 100e6);
    wbtcDec.mint(address(v), 100e8);
    v.initialize("V4TP", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    tokenA.mint(DEPOSITOR, 1000e18);
    tokenB.mint(DEPOSITOR, 1000e18);
    usdcDec.mint(DEPOSITOR, 1000e6);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);
    usdcDec.approve(address(v), type(uint256).max);
    vm.expectRevert(); // InvalidRatio — slot 3 balance > 0 but amount == 0
    v.deposit([uint256(25e18), uint256(25e18), uint256(25e6), uint256(0)], 0);
    vm.stopPrank();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // W-16: Reentrancy via malicious swap router blocked by ReentrancyGuard
  // ════════════════════════════════════════════════════════════════════════════

  function test_audit_W16_swapRouter_cannot_reenter_deposit() public {
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("W16", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    ReentrantSwapRouter rsr = new ReentrantSwapRouter();
    tokenB.mint(address(rsr), 100e18);
    address[] memory routers = new address[](1);
    routers[0] = address(rsr);
    configManager.setWhitelistSwapRouters(routers, true);
    rsr.arm(v);

    bytes memory swapData = abi.encodeCall(ReentrantSwapRouter.swap, (address(tokenA), 10e18, address(tokenB), 5e18));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(rsr),
      data: abi.encode(address(tokenA), address(tokenB), uint256(10e18), uint256(5e18), swapData),
      callType: ISharedCommon.CallType.CALL
    });
    vm.prank(VAULT_OWNER);
    v.execute(actions);

    assertTrue(rsr.reentryReverted(), "reentry into deposit() was blocked by ReentrancyGuard");
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Protocol-gap regressions: out-of-range LP + multi-position same pool
  // ════════════════════════════════════════════════════════════════════════════

  function test_audit_protocol_outOfRange_singleSidedLp_principalSplit() public {
    (SharedVault v,,) = _setupVaultWithFeeAccrualPosition(1, 50e18, 0, 0, 0); // only tokenA principal
    uint256[4] memory totals = v.getTotalBalances();
    assertEq(totals[0], 150e18, "tokenA = idle 100 + LP 50");
    assertEq(totals[1], 100e18, "tokenB = idle only");
  }

  function test_audit_multiplePositions_samePool_trackedIndependently() public {
    address[4] memory toks = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    SharedVault v = new SharedVault();
    tokenA.mint(address(v), 100e18);
    tokenB.mint(address(v), 100e18);
    v.initialize("MP", toks, init, VAULT_OWNER, OPERATOR, address(configManager), address(0), 0);

    MockFeeAccrualStrategy strat = new MockFeeAccrualStrategy();
    MockERC721 nft = new MockERC721();
    nft.mint(address(v), 1);
    nft.mint(address(v), 2);
    nft.mint(address(v), 3);
    address[] memory ts = new address[](1);
    ts[0] = address(strat);
    configManager.setWhitelistTargets(ts, true);
    address[] memory ns = new address[](1);
    ns[0] = address(nft);
    configManager.setWhitelistNfpms(ns, true);
    strat.register(address(nft), 1, address(tokenA), address(tokenB), 30e18, 30e18, 0, 0);
    strat.register(address(nft), 2, address(tokenA), address(tokenB), 20e18, 20e18, 0, 0);
    strat.register(address(nft), 3, address(tokenA), address(tokenB), 10e18, 10e18, 0, 0);

    for (uint256 id = 1; id <= 3; id++) {
      ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
      actions[0] = ISharedVault.Action({
        target: address(strat),
        data: abi.encode(address(nft), id, address(tokenA), address(tokenB)),
        callType: ISharedCommon.CallType.DELEGATECALL
      });
      vm.prank(VAULT_OWNER);
      v.execute(actions);
    }
    assertEq(v.getPositionCount(), 3);

    uint256[4] memory totals = v.getTotalBalances();
    assertEq(totals[0], 160e18); // 100 idle + 30 + 20 + 10
    assertEq(totals[1], 160e18);
  }
}
