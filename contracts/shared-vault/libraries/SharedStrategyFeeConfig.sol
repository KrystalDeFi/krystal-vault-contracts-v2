// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";

/// @title SharedStrategyFeeConfig
/// @notice `FeeConfig` for proportional LP exits (`LpFeeTaker`) when strategies run as the vault (delegatecall).
///         V3-style `execute` paths set fee Q64 on `IV3Utils` calldata; V4 exit Q64 is built in `SharedV4Strategy`.
library SharedStrategyFeeConfig {
  /// @notice `FeeConfig` for proportional LP exit (`LpFeeTaker`). Platform bps from config; withdraw exits never charge gas on principal.
  function performanceFeeConfig(uint16 vaultOwnerFeeBasisPoint) internal view returns (ICommon.FeeConfig memory fc) {
    ISharedVault v = ISharedVault(address(this));
    ISharedConfigManager cm = v.configManager();
    uint16 platformBps = cm.platformFeeBasisPoint();
    require(platformBps <= 10_000, ISharedCommon.InvalidFeeBasisPoint());
    fc.vaultOwner = v.vaultOwner();
    fc.vaultOwnerFeeBasisPoint = vaultOwnerFeeBasisPoint;
    fc.platformFeeRecipient = cm.feeRecipient();
    fc.platformFeeBasisPoint = platformBps;
    fc.gasFeeX64 = 0;
    fc.gasFeeRecipient = address(0);
  }
}
