// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedStrategyGuards } from "../../contracts/shared-vault/libraries/SharedStrategyGuards.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IHooks as IUniV4Hooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @dev Thin external wrappers so the `internal` guard functions can be called through a real
///      call boundary (and thus `vm.expectRevert`-tested). The guards inline into this harness,
///      so this exercises the exact bytecode that inlines into the strategy libraries.
contract LiquidityHookGuardHarness {
  function cl(bytes32 parameters) external pure {
    SharedStrategyGuards.requireNoLiquidityHookCL(parameters);
  }

  function v4(address hooks) external pure {
    SharedStrategyGuards.requireNoLiquidityHookV4(IUniV4Hooks(hooks));
  }
}

/// @notice Auto-gate: a position is refused at mint when its pool hook intercepts liquidity ADD or
///         REMOVE (registers before/after{Add,Remove}Liquidity). Those callbacks may require
///         non-empty hookData, and the permissionless deposit/withdraw/adjust paths pass empty
///         bytes — an add-hook would freeze deposits, a remove-hook would freeze withdrawals. The
///         common swap-side hooks (dynamic fees, fee discounts, MEV/arb redistribution) register
///         only swap/initialize callbacks, so they are NOT affected and still pass.
contract SharedLiquidityHookGateTest is Test {
  // PancakeSwap Infinity registration bitmap offsets (infinity-core ICLHooks).
  uint8 internal constant CL_BEFORE_ADD_OFFSET = 2;
  uint8 internal constant CL_AFTER_ADD_OFFSET = 3;
  uint8 internal constant CL_BEFORE_REMOVE_OFFSET = 4;
  uint8 internal constant CL_AFTER_REMOVE_OFFSET = 5;
  uint8 internal constant CL_BEFORE_SWAP_OFFSET = 6;

  // Uniswap v4 hook-address permission flags (v4-core Hooks).
  uint160 internal constant V4_BEFORE_ADD_FLAG = uint160(1) << 11;
  uint160 internal constant V4_AFTER_ADD_FLAG = uint160(1) << 10;
  uint160 internal constant V4_BEFORE_REMOVE_FLAG = uint160(1) << 9;
  uint160 internal constant V4_AFTER_REMOVE_FLAG = uint160(1) << 8;
  uint160 internal constant V4_BEFORE_SWAP_FLAG = uint160(1) << 7;

  LiquidityHookGuardHarness internal harness;

  function setUp() public {
    harness = new LiquidityHookGuardHarness();
  }

  function _clParamsWithOffset(uint8 offset) internal pure returns (bytes32) {
    return bytes32(uint256(1) << offset);
  }

  // ----- PancakeSwap Infinity: reject any add/remove-liquidity hook -----

  function test_CL_rejects_beforeAddLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.cl(_clParamsWithOffset(CL_BEFORE_ADD_OFFSET));
  }

  function test_CL_rejects_afterAddLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.cl(_clParamsWithOffset(CL_AFTER_ADD_OFFSET));
  }

  function test_CL_rejects_beforeRemoveLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.cl(_clParamsWithOffset(CL_BEFORE_REMOVE_OFFSET));
  }

  function test_CL_rejects_afterRemoveLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.cl(_clParamsWithOffset(CL_AFTER_REMOVE_OFFSET));
  }

  function test_CL_allows_hookless_pool() public view {
    harness.cl(bytes32(0));
  }

  function test_CL_allows_swapOnlyHook() public view {
    // Mirrors dynamic-fee / fee-discount / MEV hooks: swap-side only.
    harness.cl(_clParamsWithOffset(CL_BEFORE_SWAP_OFFSET));
  }

  // ----- Uniswap V4: reject any add/remove-liquidity hook -----

  function test_V4_rejects_beforeAddLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.v4(address(V4_BEFORE_ADD_FLAG));
  }

  function test_V4_rejects_afterAddLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.v4(address(V4_AFTER_ADD_FLAG));
  }

  function test_V4_rejects_beforeRemoveLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.v4(address(V4_BEFORE_REMOVE_FLAG));
  }

  function test_V4_rejects_afterRemoveLiquidityHook() public {
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.v4(address(V4_AFTER_REMOVE_FLAG));
  }

  function test_V4_allows_hookless_pool() public view {
    harness.v4(address(0));
  }

  function test_V4_allows_swapOnlyHook() public view {
    // Mirrors KyberSwap FairFlow / Uniswap v4 dynamic fees: swap-side only.
    harness.v4(address(V4_BEFORE_SWAP_FLAG));
  }
}
