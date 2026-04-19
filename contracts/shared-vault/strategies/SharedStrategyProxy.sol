// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { SharedStrategyBeacon } from "./SharedStrategyBeacon.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { Withdrawable } from "../../common/Withdrawable.sol";

/// @title SharedStrategyProxy
/// @notice Upgradeable proxy for a SharedVault strategy type.
///
///         Storage-collision safety
///         ─────────────────────────
///         SharedVault calls strategies via delegatecall, meaning the proxy's code runs in
///         SharedVault's storage context. Storing the implementation address in a regular
///         storage slot would collide with SharedVault's own layout.
///
///         This proxy avoids collision by keeping the beacon address as an `immutable` —
///         immutables are embedded in contract bytecode, not in storage, so they are readable
///         in any delegatecall context without touching storage slots.
///
///         The beacon (a separate contract) stores the implementation in its own storage.
///         Fetching it is an external call, which always executes in the beacon's context.
///
///         Call flow
///         ─────────
///         SharedVault  --delegatecall-->  SharedStrategyProxy (beacon read, then delegatecall)
///                                         └──delegatecall──>  StrategyImpl (runs as vault)
///
///         For getPositionAmounts (regular call, not delegatecall):
///         SharedVault  --call-->  SharedStrategyProxy (beacon read, then delegatecall)
///                                 └──delegatecall──>  StrategyImpl (runs as proxy)
///
/// @dev Deploy one proxy per strategy type (V3, Aerodrome, PancakeV3, V4).
///      Whitelist the proxy address in SharedConfigManager — never needs re-whitelisting on upgrade.
///      To upgrade: call SharedStrategyBeacon.setImplementation(newImpl).
contract SharedStrategyProxy is Withdrawable {
  /// @notice The beacon that holds the current implementation address.
  ///         Stored as immutable to avoid storage-collision with SharedVault when delegatecalled.
  SharedStrategyBeacon public immutable beacon;

  constructor(address _beacon) {
    require(_beacon != address(0), ISharedCommon.ZeroAddress());
    beacon = SharedStrategyBeacon(_beacon);
  }

  /// @dev Only the beacon owner can sweep accidentally stuck tokens.
  function _checkWithdrawPermission() internal view override {
    require(msg.sender == beacon.owner(), ISharedCommon.Unauthorized());
  }

  /// @dev Forwards every call to the current implementation via delegatecall.
  ///      Uses raw assembly so return data and reverts are propagated byte-for-byte.
  fallback() external payable {
    address impl = beacon.implementation();
    assembly {
      calldatacopy(0, 0, calldatasize())
      let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch ok
      case 0 { revert(0, returndatasize()) }
      default { return(0, returndatasize()) }
    }
  }

  /// @dev Accept ETH so accidentally sent native tokens can be recovered via sweepNativeToken().
  receive() external payable {}
}
