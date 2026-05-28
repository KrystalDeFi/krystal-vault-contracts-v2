// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
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

  function balanceOf(address owner) external view returns (uint256) {
    return ownerOf[1] == owner ? 1 : 0;
  }

  function positions(uint256) external view returns (
    uint96,
    address,
    address,
    address,
    uint24,
    int24,
    int24,
    uint128,
    uint256,
    uint256,
    uint128,
    uint128
  ) {
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

  function increaseLiquidity(INFPM.IncreaseLiquidityParams calldata params)
    external
    returns (uint128 addedLiquidity, uint256 amount0, uint256 amount1)
  {
    amount0 = params.amount0Desired;
    amount1 = params.amount1Desired;
    if (amount0 > 0) IERC20(token0).transferFrom(msg.sender, address(this), amount0);
    if (amount1 > 0) IERC20(token1).transferFrom(msg.sender, address(this), amount1);
    increased0 += amount0;
    increased1 += amount1;
    addedLiquidity = uint128(amount0 + amount1);
    liquidity += addedLiquidity;
  }

  function safeTransferFrom(address, address, uint256, bytes calldata) external {}
}

contract NativeStrategyNoopV3Utils {
  function swapAndIncreaseLiquidity(IV3Utils.SwapAndIncreaseLiquidityParams calldata)
    external
    payable
    returns (IV3Utils.SwapAndIncreaseLiquidityResult memory result)
  {
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

  function _takeTokenFees(address token, uint256 amount, FeeConfig memory feeConfig) private returns (uint256 totalFee) {
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

  function executeStrategy(address strategy, bytes memory data) external returns (ISharedStrategy.PositionChange[] memory changes) {
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
    cm.initialize(address(this), new address[](0), new address[](0), platformRecipient, 1_000, nfpms, new address[](0));

    vault = new NativeStrategyVaultHarness(cm, vaultOwner, 500);
    vault.addVaultToken(address(token0));
    vault.addVaultToken(address(token1));
    nfpm.setOwner(1, address(vault));
    token0.mint(address(vault), 10_000);
    token1.mint(address(vault), 20_000);

    strategy = new SharedV3Strategy(address(new NativeStrategyNoopV3Utils()), address(feeTaker));
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

  function test_v3_compound_collects_generated_fees_and_distributes_platform_owner_gas() public {
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
      abi.encode(SharedV3Strategy.OperationType.SAFE_TRANSFER_NFT),
      abi.encode(address(nfpm), uint256(1), instructions)
    );

    vm.expectEmit(true, true, true, true, address(feeTaker));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.GAS, automator, address(token0), 250);
    vm.expectEmit(true, true, true, true, address(feeTaker));
    emit IFeeTaker.FeeCollected(address(vault), IFeeTaker.FeeType.GAS, automator, address(token1), 500);

    vm.prank(automator);
    vault.executeStrategy(address(strategy), data);

    assertEq(token0.balanceOf(platformRecipient), 100, "token0 platform fee");
    assertEq(token1.balanceOf(platformRecipient), 200, "token1 platform fee");
    assertEq(token0.balanceOf(vaultOwner), 50, "token0 vault owner fee");
    assertEq(token1.balanceOf(vaultOwner), 100, "token1 vault owner fee");
    assertEq(token0.balanceOf(automator), 250, "token0 gas fee");
    assertEq(token1.balanceOf(automator), 500, "token1 gas fee");
    assertEq(nfpm.increased0(), 600, "net token0 generated fees compounded");
    assertEq(nfpm.increased1(), 1_200, "net token1 generated fees compounded");
  }
}
