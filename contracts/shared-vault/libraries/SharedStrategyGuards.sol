// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";

import { Hooks as PancakeInfinityHooks } from "infinity-core/src/libraries/Hooks.sol";
import {
  HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET,
  HOOKS_AFTER_ADD_LIQUIDITY_OFFSET,
  HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET,
  HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET
} from "infinity-core/src/pool-cl/interfaces/ICLHooks.sol";
import { IHooks as IUniV4Hooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks as UniV4Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @title SharedStrategyGuards
/// @notice NFPM whitelist checks for SharedVault strategies (defense in depth vs vault-level checks).
library SharedStrategyGuards {
  /// @param nfpm NFT / position manager address (V3 NFPM or V4 position manager)
  function requireWhitelistedNfpm(ISharedConfigManager cm, address nfpm) internal view {
    require(nfpm != address(0), ISharedCommon.ZeroAddress());
    require(cm.isWhitelistedNfpm(nfpm), ISharedCommon.InvalidNfpm(nfpm));
  }

  /// @notice PancakeSwap Infinity: reject pools whose hook intercepts liquidity ADD or REMOVAL.
  /// @dev The CL PoolManager only routes an add (`liquidityDelta > 0`) or a remove
  ///      (`liquidityDelta <= 0`, including the zero-liquidity fee-sync collect) through the hook
  ///      when the corresponding before/after{Add,Remove}Liquidity bit is registered in
  ///      `PoolKey.parameters`. If none are registered, the hook never runs on the permissionless
  ///      deposit/withdraw/adjust liquidity paths, so empty hookData is provably safe — an
  ///      add-hook could otherwise freeze deposits, a remove-hook could freeze withdrawals. Common
  ///      swap-side hooks (dynamic fees, fee discounts, oracles, MEV) register only swap/initialize
  ///      callbacks and pass.
  /// @param parameters The `PoolKey.parameters` bitmap; offsets 2/3 add, 4/5 remove.
  function requireNoLiquidityHookCL(bytes32 parameters) internal pure {
    if (
      PancakeInfinityHooks.hasOffsetEnabled(parameters, HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET)
        || PancakeInfinityHooks.hasOffsetEnabled(parameters, HOOKS_AFTER_ADD_LIQUIDITY_OFFSET)
        || PancakeInfinityHooks.hasOffsetEnabled(parameters, HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET)
        || PancakeInfinityHooks.hasOffsetEnabled(parameters, HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET)
    ) revert ISharedCommon.UnsupportedLiquidityHook();
  }

  /// @notice Uniswap V4: reject pools whose hook intercepts liquidity ADD or REMOVAL.
  /// @dev V4 encodes hook permissions in the hook address bits. A hook without any
  ///      before/after{Add,Remove}Liquidity permission is never invoked on the permissionless
  ///      deposit/withdraw paths, so empty hookData is provably safe. `address(0)` (hookless) has
  ///      no permission bits and passes; swap-side hooks (e.g. dynamic fees, FairFlow) pass too.
  /// @param hooks The pool's hook; permission bits live in the hook address.
  function requireNoLiquidityHookV4(IUniV4Hooks hooks) internal pure {
    if (
      UniV4Hooks.hasPermission(hooks, UniV4Hooks.BEFORE_ADD_LIQUIDITY_FLAG)
        || UniV4Hooks.hasPermission(hooks, UniV4Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        || UniV4Hooks.hasPermission(hooks, UniV4Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)
        || UniV4Hooks.hasPermission(hooks, UniV4Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
    ) revert ISharedCommon.UnsupportedLiquidityHook();
  }
}
