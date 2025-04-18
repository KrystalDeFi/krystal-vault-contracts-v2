// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../interfaces/core/IConfigManager.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/ICommon.sol";
import { InventoryLib } from "../libraries/InventoryLib.sol";

abstract contract VaultStorage {
  uint256 public constant SHARES_PRECISION = 1e4;
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  IConfigManager public configManager;

  address internal _vaultOwner;
  address internal _WETH;
  address public vaultFactory;
  ICommon.VaultConfig internal vaultConfig;

  InventoryLib.Inventory internal inventory;
  uint256 lastAllocateBlockNumber;
}
