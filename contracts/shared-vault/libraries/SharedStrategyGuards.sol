// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { IV3Utils } from "../../private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

/// @title SharedStrategyGuards
/// @notice NFPM and swap-router whitelist checks for SharedVault strategies (defense in depth vs vault-level checks).
library SharedStrategyGuards {
  /// @param nfpm NFT / position manager address (V3 NFPM or V4 position manager)
  function requireWhitelistedNfpm(ISharedConfigManager cm, address nfpm) internal view {
    require(nfpm != address(0), ISharedCommon.ZeroAddress());
    require(cm.isWhitelistedNfpm(nfpm), ISharedCommon.InvalidNfpm(nfpm));
  }

  /// @dev V3Utils swap calldata is `abi.encode(allowanceTarget, data)` per `IV3Utils` (0x-style router + calldata).
  function requireWhitelistedOxSwapData(ISharedConfigManager cm, bytes memory swapData) internal view {
    if (swapData.length == 0) return;
    (address allowanceTarget, ) = abi.decode(swapData, (address, bytes));
    require(cm.isWhitelistedSwapRouter(allowanceTarget), ISharedCommon.InvalidSwapRouter(allowanceTarget));
  }

  function requireWhitelistedV3SwapRoutersSwapAndMint(
    ISharedConfigManager cm,
    IV3Utils.SwapAndMintParams memory p
  ) internal view {
    requireWhitelistedOxSwapData(cm, p.swapData0);
    requireWhitelistedOxSwapData(cm, p.swapData1);
  }

  function requireWhitelistedV3SwapRoutersSwapAndIncrease(
    ISharedConfigManager cm,
    IV3Utils.SwapAndIncreaseLiquidityParams memory p
  ) internal view {
    requireWhitelistedOxSwapData(cm, p.swapData0);
    requireWhitelistedOxSwapData(cm, p.swapData1);
  }

  function requireWhitelistedV3SwapRoutersInstructions(
    ISharedConfigManager cm,
    IV3Utils.Instructions memory ins
  ) internal view {
    requireWhitelistedOxSwapData(cm, ins.swapData0);
    requireWhitelistedOxSwapData(cm, ins.swapData1);
  }
}
