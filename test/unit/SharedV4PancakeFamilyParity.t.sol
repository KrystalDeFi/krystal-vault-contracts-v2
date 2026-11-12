// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Cross-family parity, position-manager families: the StrategyFamilyParityBase properties run against
// SharedV4Strategy and SharedPancakeV4Strategy (forks: keep both suites mirrored) over faithful Uniswap V4 /
// PancakeSwap Infinity mocks (test/helpers/FaithfulV4Mocks.sol, FaithfulPancakeV4Mocks.sol). Twin of
// SharedV3AerodromeFamilyParity.t.sol.

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { PoolKey as PancakePoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency as PancakeCurrency } from "infinity-core/src/types/Currency.sol";
import { IHooks as PancakeHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager as PancakePoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import { Actions as PancakeActions } from "infinity-periphery/src/libraries/Actions.sol";

import { ISharedV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { ISharedPancakeV4Utils } from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";
import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";

import { StrategyFamilyParityBase } from "../helpers/StrategyFamilyParity.sol";
import { FaithfulPermit2 } from "../helpers/FaithfulTokens.sol";
import { FaithfulV4PoolManager, FaithfulV4PositionManager } from "../helpers/FaithfulV4Mocks.sol";
import { FaithfulCLPoolManager, FaithfulCLPositionManager } from "../helpers/FaithfulPancakeV4Mocks.sol";

/// @dev Adapter shared by the two position-manager families: Permit2 settlement and the pool manager's custody.
abstract contract PosmFamilyParity is StrategyFamilyParityBase {
  FaithfulPermit2 internal permit2;
  address internal manager;

  function _custody() internal view override returns (address) {
    return manager;
  }

  function _assertNoApprovalsLeft() internal view override {
    assertEq(token0.allowance(address(vault), address(permit2)), 0, "no token0 allowance left to Permit2");
    assertEq(token1.allowance(address(vault), address(permit2)), 0, "no token1 allowance left to Permit2");
    (uint160 permitted0,,) = permit2.allowance(address(vault), address(token0), nfpm);
    (uint160 permitted1,,) = permit2.allowance(address(vault), address(token1), nfpm);
    assertEq(permitted0, 0, "no token0 Permit2 allowance left to the position manager");
    assertEq(permitted1, 0, "no token1 Permit2 allowance left to the position manager");
  }

  /// @dev The minter's approvals for a MINT_POSITION + SETTLE_PAIR through Permit2.
  function _approveMint(uint256 amount0, uint256 amount1) internal {
    token0.approve(address(permit2), amount0);
    token1.approve(address(permit2), amount1);
    permit2.approve(address(token0), nfpm, uint160(amount0), uint48(block.timestamp));
    permit2.approve(address(token1), nfpm, uint160(amount1), uint48(block.timestamp));
  }

  function _liquidityForMint(uint256 amount0, uint256 amount1) internal pure returns (uint128) {
    return LiquidityAmounts.getLiquidityForAmounts(
      SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(TICK_LOWER), TickMath.getSqrtPriceAtTick(TICK_UPPER), amount0, amount1
    );
  }
}

/// @dev Uniswap V4 family.
contract SharedV4FamilyParityTest is PosmFamilyParity {
  PoolKey internal key;

  function _deployFamily() internal override returns (address, address) {
    FaithfulV4PoolManager poolManager = new FaithfulV4PoolManager();
    manager = address(poolManager);
    permit2 = new FaithfulPermit2();
    FaithfulV4PositionManager posm = new FaithfulV4PositionManager(poolManager, permit2);
    key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: 500,
      tickSpacing: 10,
      hooks: IHooks(address(0))
    });
    poolManager.initialize(key, SQRT_PRICE_1_1);
    return (address(posm), address(new SharedV4Strategy(SWAP_ROUTER)));
  }

  function _mintPosition(address owner, uint256 amount0, uint256 amount1) internal override returns (uint256 id) {
    _fund(owner, token0, amount0);
    _fund(owner, token1, amount1);
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(
      key,
      TICK_LOWER,
      TICK_UPPER,
      uint256(_liquidityForMint(amount0, amount1)),
      uint128(amount0),
      uint128(amount1),
      owner,
      bytes("")
    );
    params[1] = abi.encode(key.currency0, key.currency1);
    vm.startPrank(owner);
    _approveMint(amount0, amount1);
    id = FaithfulV4PositionManager(nfpm).nextTokenId();
    FaithfulV4PositionManager(nfpm)
      .modifyLiquidities(
        abi.encode(abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR)), params), block.timestamp
      );
    vm.stopPrank();
  }

  function _liquidityOf(uint256 id) internal view override returns (uint128) {
    return FaithfulV4PositionManager(nfpm).getPositionLiquidity(id);
  }

  function _uncollectedFees(uint256 id) internal view override returns (uint256, uint256) {
    return FaithfulV4PositionManager(nfpm).pendingFees(id);
  }

  function _accrueFees(uint256 fee0, uint256 fee1) internal override {
    _fund(address(this), token0, fee0);
    _fund(address(this), token1, fee1);
    token0.approve(manager, fee0);
    token1.approve(manager, fee1);
    FaithfulV4PoolManager(manager).accrueFees(key, fee0, fee1);
  }

  function _compoundData(uint256 id) internal view override returns (bytes memory) {
    ISharedV4Utils.CompoundFeesParams memory params;
    params.increaseParams.deadline = block.timestamp;
    return _instructionsData(id, ISharedV4Utils.UtilActions.COMPOUND, abi.encode(params));
  }

  function _decreaseData(uint256 id, uint128 liquidity) internal view override returns (bytes memory) {
    ISharedV4Utils.DecreaseAndSwapParams memory params;
    params.decreaseParams.liquidity = liquidity;
    params.decreaseParams.deadline = block.timestamp;
    params.swapDestToken = key.currency0;
    return _instructionsData(id, ISharedV4Utils.UtilActions.DECREASE_AND_SWAP, abi.encode(params));
  }

  function _increaseData(uint256 id, uint256 amount0, uint256 amount1) internal view override returns (bytes memory) {
    ISharedV4Utils.SwapAndIncreaseParams memory params;
    params.posm = nfpm;
    params.tokenId = id;
    params.increaseParams.deadline = block.timestamp;
    params.inputTokens = new ISharedV4Utils.InputTokenParams[](2);
    params.inputTokens[0] = ISharedV4Utils.InputTokenParams(key.currency0, amount0);
    params.inputTokens[1] = ISharedV4Utils.InputTokenParams(key.currency1, amount1);
    return bytes.concat(
      abi.encode(SharedV4Strategy.OperationType.EXECUTE),
      abi.encode(
        nfpm,
        id,
        abi.encodeCall(ISharedV4Utils.swapAndIncrease, (params)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );
  }

  function _instructionsData(uint256 id, ISharedV4Utils.UtilActions action, bytes memory params)
    internal
    view
    returns (bytes memory)
  {
    bytes memory instruction = abi.encode(ISharedV4Utils.Instructions({ action: action, params: params }));
    return
      bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), abi.encode(nfpm, id, instruction));
  }
}

/// @dev PancakeSwap Infinity family (fork of the V4 strategy; keep mirrored with SharedV4FamilyParityTest).
contract SharedPancakeV4FamilyParityTest is PosmFamilyParity {
  PancakePoolKey internal key;

  function _deployFamily() internal override returns (address, address) {
    FaithfulCLPoolManager poolManager = new FaithfulCLPoolManager();
    manager = address(poolManager);
    permit2 = new FaithfulPermit2();
    FaithfulCLPositionManager posm = new FaithfulCLPositionManager(poolManager, permit2);
    key = PancakePoolKey({
      currency0: PancakeCurrency.wrap(address(token0)),
      currency1: PancakeCurrency.wrap(address(token1)),
      hooks: PancakeHooks(address(0)),
      poolManager: PancakePoolManager(address(poolManager)),
      fee: 500,
      parameters: bytes32(uint256(uint24(10)) << 16)
    });
    poolManager.initialize(key, SQRT_PRICE_1_1);
    return (address(posm), address(new SharedPancakeV4Strategy(SWAP_ROUTER)));
  }

  function _mintPosition(address owner, uint256 amount0, uint256 amount1) internal override returns (uint256 id) {
    _fund(owner, token0, amount0);
    _fund(owner, token1, amount1);
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(
      key,
      TICK_LOWER,
      TICK_UPPER,
      uint256(_liquidityForMint(amount0, amount1)),
      uint128(amount0),
      uint128(amount1),
      owner,
      bytes("")
    );
    params[1] = abi.encode(key.currency0, key.currency1);
    vm.startPrank(owner);
    _approveMint(amount0, amount1);
    id = FaithfulCLPositionManager(nfpm).nextTokenId();
    FaithfulCLPositionManager(nfpm)
      .modifyLiquidities(
        abi.encode(abi.encodePacked(uint8(PancakeActions.CL_MINT_POSITION), uint8(PancakeActions.SETTLE_PAIR)), params),
        block.timestamp
      );
    vm.stopPrank();
  }

  function _liquidityOf(uint256 id) internal view override returns (uint128) {
    return FaithfulCLPositionManager(nfpm).getPositionLiquidity(id);
  }

  function _uncollectedFees(uint256 id) internal view override returns (uint256, uint256) {
    return FaithfulCLPositionManager(nfpm).pendingFees(id);
  }

  function _accrueFees(uint256 fee0, uint256 fee1) internal override {
    _fund(address(this), token0, fee0);
    _fund(address(this), token1, fee1);
    token0.approve(manager, fee0);
    token1.approve(manager, fee1);
    FaithfulCLPoolManager(manager).accrueFees(key, fee0, fee1);
  }

  function _compoundData(uint256 id) internal view override returns (bytes memory) {
    ISharedPancakeV4Utils.CompoundFeesParams memory params;
    params.increaseParams.deadline = block.timestamp;
    return _instructionsData(id, ISharedPancakeV4Utils.UtilActions.COMPOUND, abi.encode(params));
  }

  function _decreaseData(uint256 id, uint128 liquidity) internal view override returns (bytes memory) {
    ISharedPancakeV4Utils.DecreaseAndSwapParams memory params;
    params.decreaseParams.liquidity = liquidity;
    params.decreaseParams.deadline = block.timestamp;
    params.swapDestToken = key.currency0;
    return _instructionsData(id, ISharedPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, abi.encode(params));
  }

  function _increaseData(uint256 id, uint256 amount0, uint256 amount1) internal view override returns (bytes memory) {
    ISharedPancakeV4Utils.SwapAndIncreaseParams memory params;
    params.posm = nfpm;
    params.tokenId = id;
    params.increaseParams.deadline = block.timestamp;
    params.inputTokens = new ISharedPancakeV4Utils.InputTokenParams[](2);
    params.inputTokens[0] = ISharedPancakeV4Utils.InputTokenParams(key.currency0, amount0);
    params.inputTokens[1] = ISharedPancakeV4Utils.InputTokenParams(key.currency1, amount1);
    return bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
      abi.encode(
        nfpm,
        id,
        abi.encodeCall(ISharedPancakeV4Utils.swapAndIncrease, (params)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );
  }

  function _instructionsData(uint256 id, ISharedPancakeV4Utils.UtilActions action, bytes memory params)
    internal
    view
    returns (bytes memory)
  {
    bytes memory instruction = abi.encode(ISharedPancakeV4Utils.Instructions({ action: action, params: params }));
    return bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), abi.encode(nfpm, id, instruction)
    );
  }
}
