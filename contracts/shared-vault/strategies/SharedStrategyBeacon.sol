// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";

/// @title SharedStrategyBeacon
/// @notice Stores the current implementation address for a SharedVault strategy type.
///         Owned by the protocol multisig; upgrading calls setImplementation().
///         All SharedStrategyProxy instances pointing to this beacon immediately use the
///         new implementation without any per-vault or per-position migration.
contract SharedStrategyBeacon is Ownable {
  address public implementation;

  event ImplementationUpgraded(address indexed oldImpl, address indexed newImpl);

  constructor(address _implementation, address _owner) Ownable(_owner) {
    require(_implementation != address(0), ISharedCommon.ZeroAddress());
    implementation = _implementation;
  }

  /// @notice Upgrade the strategy implementation. Only the owner (protocol deployer) can call this.
  /// @param newImplementation New strategy logic contract address
  function setImplementation(address newImplementation) external onlyOwner {
    require(newImplementation != address(0), ISharedCommon.ZeroAddress());
    emit ImplementationUpgraded(implementation, newImplementation);
    implementation = newImplementation;
  }
}
