// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IFeeTaker } from "../../contracts/public-vault/interfaces/strategies/IFeeTaker.sol";
import { ILpFeeTaker } from "../../contracts/public-vault/interfaces/strategies/ILpFeeTaker.sol";

contract NativeStrategyToken {
  string public name;
  string public symbol;
  uint8 public decimals = 18;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _symbol) {
    name = _symbol;
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

contract NativeStrategyPool {}

contract NativeStrategyFactory {
  address public immutable pool;

  constructor(address _pool) {
    pool = _pool;
  }

  function getPool(address, address, uint24) external view returns (address) {
    return pool;
  }
}

contract NativeStrategyNfpm {
  address public immutable factory;
  address public immutable token0;
  address public immutable token1;

  uint128 public liquidity = 1_000_000;
  uint256 public collectAmount0;
  uint256 public collectAmount1;
  uint256 public principalOut0;
  uint256 public principalOut1;
  uint256 public collectCalls;
  uint256 public increased0;
  uint256 public increased1;

  mapping(uint256 => address) public ownerOf;

  constructor(address _factory, address _token0, address _token1) {
    factory = _factory;
    token0 = _token0;
    token1 = _token1;
  }

  function setOwner(uint256 tokenId, address owner) external {
    ownerOf[tokenId] = owner;
  }

  function setCollectFees(uint256 amount0, uint256 amount1) external {
    collectAmount0 = amount0;
    collectAmount1 = amount1;
  }

  function setPrincipalOut(uint256 amount0, uint256 amount1) external {
    principalOut0 = amount0;
    principalOut1 = amount1;
  }

  function balanceOf(address owner) external view returns (uint256) {
    return ownerOf[1] == owner ? 1 : 0;
  }

  function positions(
    uint256
  )
    external
    view
    returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    return (
      0,
      address(0),
      token0,
      token1,
      500,
      -60,
      60,
      liquidity,
      0,
      0,
      uint128(collectAmount0),
      uint128(collectAmount1)
    );
  }

  function collect(INFPM.CollectParams calldata params) external returns (uint256 amount0, uint256 amount1) {
    collectCalls++;
    amount0 = collectAmount0;
    amount1 = collectAmount1;
    collectAmount0 = 0;
    collectAmount1 = 0;
    if (amount0 > 0) NativeStrategyToken(token0).mint(params.recipient, amount0);
    if (amount1 > 0) NativeStrategyToken(token1).mint(params.recipient, amount1);
  }

  function increaseLiquidity(
    INFPM.IncreaseLiquidityParams calldata params
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

  function decreaseLiquidity(
    INFPM.DecreaseLiquidityParams calldata params
  ) external returns (uint256 amount0, uint256 amount1) {
    require(params.liquidity <= liquidity, "decrease exceeds liquidity");
    liquidity -= params.liquidity;
    amount0 = principalOut0;
    amount1 = principalOut1;
    collectAmount0 = principalOut0;
    collectAmount1 = principalOut1;
  }

  function safeTransferFrom(address, address, uint256, bytes calldata) external {}
}

contract NativeStrategyNoopV3Utils {
  function swapAndIncreaseLiquidity(
    IV3Utils.SwapAndIncreaseLiquidityParams calldata
  ) external payable returns (IV3Utils.SwapAndIncreaseLiquidityResult memory result) {
    return result;
  }
}

contract NativeStrategyLpFeeTaker is ILpFeeTaker {
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

contract NativeStrategyVaultHarness {
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

contract SharedStrategyNativeExecutionTest is Test {
  uint64 internal constant GAS_FEE_X64_25_PERCENT = uint64(1 << 62);
  uint64 internal constant GAS_FEE_X64_75_PERCENT = uint64(3 << 62);
  // ~90% of the collected amount expressed as a Q64 fraction (0.9 * 2^64).
  uint64 internal constant GAS_FEE_X64_90_PERCENT = uint64((9 * (uint256(1) << 64)) / 10);

  NativeStrategyToken internal token0;
  NativeStrategyToken internal token1;
  NativeStrategyNfpm internal nfpm;
  NativeStrategyVaultHarness internal vault;
  NativeStrategyLpFeeTaker internal feeTaker;
  SharedV3Strategy internal strategy;
  address internal platformRecipient = address(0xAA01);
  address internal vaultOwner = address(0xAA02);
  address internal automator = address(0xAA03);

  function setUp() public {
    token0 = new NativeStrategyToken("NST0");
    token1 = new NativeStrategyToken("NST1");
    NativeStrategyPool pool = new NativeStrategyPool();
    NativeStrategyFactory factory = new NativeStrategyFactory(address(pool));
    nfpm = new NativeStrategyNfpm(address(factory), address(token0), address(token1));
    feeTaker = new NativeStrategyLpFeeTaker();

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), new address[](0), new address[](0), platformRecipient, 1_000, nfpms, new address[](0), new address[](0));
    cm.setMaxGasFeeX64(type(uint64).max);

    vault = new NativeStrategyVaultHarness(cm, vaultOwner, 500);
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));
    nfpm.setOwner(1, address(vault));
    token0.mint(address(vault), 10_000);
    token1.mint(address(vault), 20_000);

    strategy = new SharedV3Strategy(address(new NativeStrategyNoopV3Utils()));
  }

  function test_v3_swapAndIncrease_does_not_collect_generated_fees() public {
    nfpm.setCollectFees(1_000, 2_000);

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0,
      nfpm: address(nfpm),
      tokenId: 1,
      amount0: 100,
      amount1: 200,
      amount2: 0,
      recipient: address(0),
      deadline: block.timestamp + 1,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      protocolFeeX64: 0,
      gasFeeX64: 0
    });

    address[] memory approveTokens = new address[](2);
    approveTokens[0] = address(token0);
    approveTokens[1] = address(token1);
    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = 100;
    approveAmounts[1] = 200;

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.SWAP_AND_INCREASE),
      abi.encode(params, approveTokens, approveAmounts, uint256(0))
    );

    vault.executeStrategy(address(strategy), data);

    assertEq(nfpm.collectCalls(), 0, "increase must leave generated fees on the position");
    assertEq(nfpm.increased0(), 100, "token0 principal increased");
    assertEq(nfpm.increased1(), 200, "token1 principal increased");
  }

  function test_v3_compound_collects_generated_fees_and_routes_gas_to_fee_collector() public {
    nfpm.setCollectFees(1_000, 2_000);

    IV3Utils.Instructions memory instructions = IV3Utils.Instructions({
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
      gasFeeX64: GAS_FEE_X64_25_PERCENT
    });

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    // Fees are now settled by SharedStrategyFees (direct transfer, inlined into the strategy running in the
    // vault's delegatecall context), so FeeCollected is emitted from the vault address, in order
    // platform → owner → gas, with each token's slice transferred directly (no LpFeeTaker consolidation).
    vm.expectEmit(true, true, true, true, address(vault));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.PLATFORM, platformRecipient, address(token0), 100);
    vm.expectEmit(true, true, true, true, address(vault));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.PLATFORM, platformRecipient, address(token1), 200);
    vm.expectEmit(true, true, true, true, address(vault));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.OWNER, vaultOwner, address(token0), 50);
    vm.expectEmit(true, true, true, true, address(vault));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.OWNER, vaultOwner, address(token1), 100);
    vm.expectEmit(true, true, true, true, address(vault));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.GAS, platformRecipient, address(token0), 250);
    vm.expectEmit(true, true, true, true, address(vault));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.GAS, platformRecipient, address(token1), 500);

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    assertEq(token0.balanceOf(platformRecipient), 350, "token0 platform plus gas fee");
    assertEq(token1.balanceOf(platformRecipient), 700, "token1 platform plus gas fee");
    assertEq(token0.balanceOf(vaultOwner), 50, "token0 vault owner fee");
    assertEq(token1.balanceOf(vaultOwner), 100, "token1 vault owner fee");
    assertEq(token0.balanceOf(automator), 0, "executor receives no token0 gas fee");
    assertEq(token1.balanceOf(automator), 0, "executor receives no token1 gas fee");
    assertEq(nfpm.increased0(), 600, "net token0 generated fees compounded");
    assertEq(nfpm.increased1(), 1_200, "net token1 generated fees compounded");
  }

  function test_v3_compound_revertsWhenGasFeeExceedsConfigCap() public {
    vault.configManager().setMaxGasFeeX64(0);
    nfpm.setCollectFees(1_000, 2_000);

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), _compoundInstructions(GAS_FEE_X64_25_PERCENT))
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidGasFeeX64.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_v3_compound_revertsWhenEmptySwapDataHasMinOut() public {
    nfpm.setCollectFees(1_000, 0);

    IV3Utils.Instructions memory instructions = _compoundInstructions(0);
    instructions.targetToken = address(token1);
    instructions.amountIn0 = 1;
    instructions.amountOut0Min = 1;
    instructions.swapData0 = "";

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_v3_compound_revertsWhenTargetTokenIsNotPoolToken() public {
    nfpm.setCollectFees(1_000, 2_000);

    IV3Utils.Instructions memory instructions = _compoundInstructions(0);
    instructions.targetToken = address(0xDEAD);

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.executeStrategy(address(strategy), data);
  }

  function test_v3_withdraw_revertsWhenTargetSideHasMinOut() public {
    nfpm.setPrincipalOut(1_000, 0);

    IV3Utils.Instructions memory instructions = _compoundInstructions(0);
    instructions.whatToDo = IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
    instructions.targetToken = address(token0);
    instructions.liquidity = type(uint128).max;
    instructions.amountOut0Min = 1;

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    vm.prank(automator);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.executeStrategy(address(strategy), data);
  }

  /// @dev Unified clamp model (parity with V4/Pancake and Aerodrome): stacking a gas fee such that
  ///      platform + owner + gas exceeds 100% no longer reverts — each fee is clamped to the running
  ///      remainder (platform → owner → gas) via SharedStrategyFees, so total fee can never exceed the
  ///      collected amount and the gas fee absorbs whatever is left. Here 10% + 5% + ~90% would be 105%,
  ///      so gas is clamped to the remaining 85% and nothing is compounded.
  function test_v3_compound_clamps_when_platform_owner_gas_exceed_100pct() public {
    nfpm.setCollectFees(1_000, 2_000);

    IV3Utils.Instructions memory instructions = _compoundInstructions(GAS_FEE_X64_90_PERCENT);

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data); // no revert

    // token0 collected 1_000: platform 100 + owner 50 + gas clamped to 850 (req 900) = 1_000, 0 compounded.
    // token1 collected 2_000: platform 200 + owner 100 + gas clamped to 1_700 (req 1_800) = 2_000, 0 compounded.
    assertEq(token0.balanceOf(platformRecipient), 950, "token0 platform plus gas fee");
    assertEq(token1.balanceOf(platformRecipient), 1_900, "token1 platform plus gas fee");
    assertEq(token0.balanceOf(vaultOwner), 50, "token0 owner fee");
    assertEq(token1.balanceOf(vaultOwner), 100, "token1 owner fee");
    assertEq(token0.balanceOf(automator), 0, "executor receives no token0 gas fee");
    assertEq(token1.balanceOf(automator), 0, "executor receives no token1 gas fee");
    assertEq(nfpm.increased0(), 0, "nothing compounded (fees consumed 100%)");
    assertEq(nfpm.increased1(), 0, "nothing compounded (fees consumed 100%)");
  }

  /// @dev A large-but-valid stacked gas fee (platform=10% + owner=5% + gas=75% = 90% <= 100%) must
  ///      still succeed and settle each fee exactly, proving the cap rejects only configs that would
  ///      over-draw the collected amount — it does not over-reject legitimate stacked fees.
  function test_v3_compound_allows_large_but_valid_stacked_gas_fee() public {
    nfpm.setCollectFees(1_000, 2_000);

    IV3Utils.Instructions memory instructions = _compoundInstructions(GAS_FEE_X64_75_PERCENT);

    bytes memory data = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    // token0 collected 1_000: platform 100 + owner 50 + gas 750 = 900 fee, 100 compounded.
    // token1 collected 2_000: platform 200 + owner 100 + gas 1_500 = 1_800 fee, 200 compounded.
    assertEq(token0.balanceOf(platformRecipient), 850, "token0 platform plus gas fee");
    assertEq(token1.balanceOf(platformRecipient), 1_700, "token1 platform plus gas fee");
    assertEq(token0.balanceOf(vaultOwner), 50, "token0 owner fee");
    assertEq(token1.balanceOf(vaultOwner), 100, "token1 owner fee");
    assertEq(token0.balanceOf(automator), 0, "executor receives no token0 gas fee");
    assertEq(token1.balanceOf(automator), 0, "executor receives no token1 gas fee");
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
