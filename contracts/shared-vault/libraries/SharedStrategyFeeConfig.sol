// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ICommon } from "../../public-vault/interfaces/ICommon.sol";

/// @title SharedStrategyFeeConfig
/// @notice Platform bps `0` => config; gas X64 always caller-supplied for `execute`; withdraw exits use no gas fee.
library SharedStrategyFeeConfig {
  uint256 private constant Q64 = 0x10000000000000000;

  /// @dev `overrideBps == 0` uses stored config platform fee.
  function resolvePlatformBps(ISharedConfigManager cm, uint16 overrideBps) internal view returns (uint16) {
    uint16 bps = overrideBps == 0 ? cm.platformFeeBasisPoint() : overrideBps;
    require(bps <= 10_000, ISharedCommon.InvalidFeeBasisPoint());
    return bps;
  }

  /// @dev Q64 for V3Utils `protocolFeeX64` / `Instructions.performanceFeeX64`.
  function platformFeeX64(ISharedConfigManager cm, uint16 platformBpsOverride) internal view returns (uint64) {
    uint16 bps = resolvePlatformBps(cm, platformBpsOverride);
    if (bps == 0) return 0;
    return uint64(FullMath.mulDiv(uint256(bps), Q64, 10_000));
  }

  /// @notice `FeeConfig` for proportional LP exit (`LpFeeTaker`). Platform bps from config; withdraw exits never charge gas on principal.
  function performanceFeeConfig(uint16 vaultOwnerFeeBasisPoint) internal view returns (ICommon.FeeConfig memory fc) {
    ISharedVault v = ISharedVault(address(this));
    ISharedConfigManager cm = v.configManager();
    fc.vaultOwner = v.vaultOwner();
    fc.vaultOwnerFeeBasisPoint = vaultOwnerFeeBasisPoint;
    fc.platformFeeRecipient = cm.feeRecipient();
    fc.platformFeeBasisPoint = resolvePlatformBps(cm, 0);
    fc.gasFeeX64 = 0;
    fc.gasFeeRecipient = address(0);
  }
}
