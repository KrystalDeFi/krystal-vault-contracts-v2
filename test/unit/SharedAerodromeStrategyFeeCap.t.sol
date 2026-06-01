// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager } from "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IFeeTaker } from "../../contracts/public-vault/interfaces/strategies/IFeeTaker.sol";
import { ILpFeeTaker } from "../../contracts/public-vault/interfaces/strategies/ILpFeeTaker.sol";

// ---------------------------------------------------------------------------
// Minimal mocks (Aerodrome-shaped) used to drive SharedAerodromeStrategy.execute
// through the COMPOUND_FEES path that stacks an executor-supplied gas fee on top
// of the platform + owner performance fees.
// ---------------------------------------------------------------------------

contract AeroFeeCapToken {
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _symbol) {
    symbol = _symbol;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) {
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

contract AeroFeeCapPool {}

contract AeroFeeCapFactory {
  address public immutable pool;

  constructor(address _pool) {
    pool = _pool;
  }

  // Aerodrome CL factory: tickSpacing-based pool lookup.
  function getPool(address, address, int24) external view returns (address) {
    return pool;
  }
}

contract AeroFeeCapNfpm {
  address public immutable factory;
  address public immutable token0;
  address public immutable token1;

  uint128 public liquidity = 1_000_000;
  uint256 public collectAmount0;
  uint256 public collectAmount1;
  uint256 public increased0;
  uint256 public increased1;

  constructor(address _factory, address _token0, address _token1) {
    factory = _factory;
    token0 = _token0;
    token1 = _token1;
  }

  function setCollectFees(uint256 amount0, uint256 amount1) external {
    collectAmount0 = amount0;
    collectAmount1 = amount1;
  }

  // Aerodrome positions(): note int24 tickSpacing at index 4 (vs V3's uint24 fee).
  function positions(
    uint256
  )
    external
    view
    returns (uint96, address, address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    return (
      0,
      address(0),
      token0,
      token1,
      int24(60),
      int24(-60),
      int24(60),
      liquidity,
      0,
      0,
      uint128(collectAmount0),
      uint128(collectAmount1)
    );
  }

  function collect(
    INonfungiblePositionManager.CollectParams calldata params
  ) external returns (uint256 amount0, uint256 amount1) {
    amount0 = collectAmount0;
    amount1 = collectAmount1;
    collectAmount0 = 0;
    collectAmount1 = 0;
    if (amount0 > 0) AeroFeeCapToken(token0).mint(params.recipient, amount0);
    if (amount1 > 0) AeroFeeCapToken(token1).mint(params.recipient, amount1);
  }

  function increaseLiquidity(
    INonfungiblePositionManager.IncreaseLiquidityParams calldata params
  ) external returns (uint128 addedLiquidity, uint256 amount0, uint256 amount1) {
    amount0 = params.amount0Desired;
    amount1 = params.amount1Desired;
    if (amount0 > 0) IERC20(token0).transferFrom(msg.sender, address(this), amount0);
    if (amount1 > 0) IERC20(token1).transferFrom(msg.sender, address(this), amount1);
    increased0 += amount0;
    increased1 += amount1;
    addedLiquidity = uint128(amount0 + amount1);
    liquidity += addedLiquidity;
  }
}

/// @dev Mirrors the real LpFeeTaker fee arithmetic: platform + owner + gas summed WITHOUT a clamp.
contract AeroFeeCapLpFeeTaker is ILpFeeTaker {
  uint256 internal constant Q64 = 2 ** 64;

  function takeFees(
    address token0,
    uint256 amount0,
    address token1,
    uint256 amount1,
    FeeConfig memory feeConfig,
    address,
    address,
    address
  ) external override returns (uint256 fee0, uint256 fee1) {
    fee0 = _takeTokenFees(token0, amount0, feeConfig);
    fee1 = _takeTokenFees(token1, amount1, feeConfig);
  }

  function _takeTokenFees(
    address token,
    uint256 amount,
    FeeConfig memory feeConfig
  ) private returns (uint256 totalFee) {
    uint256 platformFee = (amount * feeConfig.platformFeeBasisPoint) / 10_000;
    if (platformFee > 0) {
      IERC20(token).transferFrom(msg.sender, feeConfig.platformFeeRecipient, platformFee);
      emit FeeCollected(msg.sender, IFeeTaker.FeeType.PLATFORM, feeConfig.platformFeeRecipient, token, platformFee);
      totalFee += platformFee;
    }

    uint256 ownerFee = (amount * feeConfig.vaultOwnerFeeBasisPoint) / 10_000;
    if (ownerFee > 0) {
      IERC20(token).transferFrom(msg.sender, feeConfig.vaultOwner, ownerFee);
      emit FeeCollected(msg.sender, IFeeTaker.FeeType.OWNER, feeConfig.vaultOwner, token, ownerFee);
      totalFee += ownerFee;
    }

    uint256 gasFee = (amount * feeConfig.gasFeeX64) / Q64;
    if (gasFee > 0) {
      IERC20(token).transferFrom(msg.sender, feeConfig.gasFeeRecipient, gasFee);
      emit FeeCollected(msg.sender, IFeeTaker.FeeType.GAS, feeConfig.gasFeeRecipient, token, gasFee);
      totalFee += gasFee;
    }
  }
}

contract AeroFeeCapVaultHarness {
  SharedConfigManager public configManager;
  address public vaultOwner;
  uint16 public vaultOwnerFeeBasisPoint;
  mapping(address => bool) public isVaultToken;

  constructor(SharedConfigManager _configManager, address _vaultOwner, uint16 _vaultOwnerFeeBasisPoint) {
    configManager = _configManager;
    vaultOwner = _vaultOwner;
    vaultOwnerFeeBasisPoint = _vaultOwnerFeeBasisPoint;
  }

  function addVaultToken(address token) external {
    isVaultToken[token] = true;
  }

  function executeStrategy(
    address strategy,
    bytes memory data
  ) external returns (ISharedStrategy.PositionChange[] memory changes) {
    (bool ok, bytes memory result) = strategy.delegatecall(abi.encodeCall(ISharedStrategy.execute, (data)));
    if (!ok) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
    changes = abi.decode(result, (ISharedStrategy.PositionChange[]));
  }
}

contract SharedAerodromeStrategyFeeCapTest is Test {
  uint64 internal constant GAS_FEE_X64_75_PERCENT = uint64(3 << 62);
  // ~90% of the collected amount expressed as a Q64 fraction (0.9 * 2^64).
  uint64 internal constant GAS_FEE_X64_90_PERCENT = uint64((9 * (uint256(1) << 64)) / 10);

  AeroFeeCapToken internal token0;
  AeroFeeCapToken internal token1;
  AeroFeeCapNfpm internal nfpm;
  AeroFeeCapVaultHarness internal vault;
  AeroFeeCapLpFeeTaker internal feeTaker;
  SharedAerodromeStrategy internal strategy;
  address internal platformRecipient = address(0xBB01);
  address internal vaultOwner = address(0xBB02);
  address internal automator = address(0xBB03);

  function setUp() public {
    token0 = new AeroFeeCapToken("AT0");
    token1 = new AeroFeeCapToken("AT1");
    AeroFeeCapPool pool = new AeroFeeCapPool();
    AeroFeeCapFactory factory = new AeroFeeCapFactory(address(pool));
    nfpm = new AeroFeeCapNfpm(address(factory), address(token0), address(token1));
    feeTaker = new AeroFeeCapLpFeeTaker();

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), new address[](0), new address[](0), platformRecipient, 1_000, nfpms, new address[](0));

    vault = new AeroFeeCapVaultHarness(cm, vaultOwner, 500);
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));
    token0.mint(address(vault), 10_000);
    token1.mint(address(vault), 20_000);

    strategy = new SharedAerodromeStrategy(address(0xCAFE));
  }

  /// @dev Unified clamp model (parity with the V4/Pancake libs): stacking a gas fee on top of platform +
  ///      owner fees such that the three combined exceed 100% no longer reverts — each fee is clamped to the
  ///      running remainder (platform → owner → gas), so the total fee can never exceed the collected amount
  ///      and the gas fee simply absorbs whatever is left. Here platform=10% + owner=5% + gas≈90% would be
  ///      105%, so gas is clamped to the remaining 85% and nothing is compounded.
  function test_aerodrome_compound_clamps_when_platform_owner_gas_exceed_100pct() public {
    nfpm.setCollectFees(1_000, 2_000);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), _compoundInstructions(GAS_FEE_X64_90_PERCENT))
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data); // no revert

    // token0 collected 1_000: platform 100 + owner 50 + gas clamped to 850 (req 900) = 1_000 total, 0 compounded.
    // token1 collected 2_000: platform 200 + owner 100 + gas clamped to 1_700 (req 1_800) = 2_000 total, 0 compounded.
    assertEq(token0.balanceOf(platformRecipient), 100, "token0 platform fee");
    assertEq(token1.balanceOf(platformRecipient), 200, "token1 platform fee");
    assertEq(token0.balanceOf(vaultOwner), 50, "token0 owner fee");
    assertEq(token1.balanceOf(vaultOwner), 100, "token1 owner fee");
    assertEq(token0.balanceOf(automator), 850, "token0 gas fee clamped to remainder");
    assertEq(token1.balanceOf(automator), 1_700, "token1 gas fee clamped to remainder");
    assertEq(nfpm.increased0(), 0, "nothing compounded (fees consumed 100%)");
    assertEq(nfpm.increased1(), 0, "nothing compounded (fees consumed 100%)");
  }

  /// @dev A large-but-valid stacked gas fee (10% + 5% + 75% = 90% <= 100%) still succeeds and
  ///      settles each fee exactly, proving the cap does not over-reject legitimate configs.
  function test_aerodrome_compound_allows_large_but_valid_stacked_gas_fee() public {
    nfpm.setCollectFees(1_000, 2_000);

    bytes memory data = bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), _compoundInstructions(GAS_FEE_X64_75_PERCENT))
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    // token0 collected 1_000: platform 100 + owner 50 + gas 750 = 900 fee, 100 compounded.
    // token1 collected 2_000: platform 200 + owner 100 + gas 1_500 = 1_800 fee, 200 compounded.
    assertEq(token0.balanceOf(platformRecipient), 100, "token0 platform fee");
    assertEq(token1.balanceOf(platformRecipient), 200, "token1 platform fee");
    assertEq(token0.balanceOf(vaultOwner), 50, "token0 owner fee");
    assertEq(token1.balanceOf(vaultOwner), 100, "token1 owner fee");
    assertEq(token0.balanceOf(automator), 750, "token0 gas fee");
    assertEq(token1.balanceOf(automator), 1_500, "token1 gas fee");
    assertEq(nfpm.increased0(), 100, "net token0 compounded");
    assertEq(nfpm.increased1(), 200, "net token1 compounded");
  }

  function _compoundInstructions(uint64 gasFeeX64) internal view returns (IV3Utils.Instructions memory) {
    return
      IV3Utils.Instructions({
        whatToDo: IV3Utils.WhatToDo.COMPOUND_FEES,
        protocol: 0,
        targetToken: address(0),
        amountRemoveMin0: 0,
        amountRemoveMin1: 0,
        amountIn0: 0,
        amountOut0Min: 0,
        swapData0: "",
        amountIn1: 0,
        amountOut1Min: 0,
        swapData1: "",
        tickLower: 0,
        tickUpper: 0,
        compoundFees: true,
        liquidity: 0,
        amountAddMin0: 0,
        amountAddMin1: 0,
        deadline: block.timestamp + 1,
        recipient: address(vault),
        unwrap: false,
        liquidityFeeX64: 0,
        performanceFeeX64: 0,
        gasFeeX64: gasFeeX64
      });
  }
}
