// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";

/// @title SharedStrategyGuards
/// @notice NFPM whitelist checks for SharedVault strategies (defense in depth vs vault-level checks).
library SharedStrategyGuards {
  /// @param nfpm NFT / position manager address (V3 NFPM or V4 position manager)
  function requireWhitelistedNfpm(ISharedConfigManager cm, address nfpm) internal view {
    require(nfpm != address(0), ISharedCommon.ZeroAddress());
    require(cm.isWhitelistedNfpm(nfpm), ISharedCommon.InvalidNfpm(nfpm));
  }
}
