// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import "./SharedVaultConfig.sol";

/// @dev Deploys SharedV3Strategy + LpFeeTaker.
///      Pre-deployed by echidna via deployContracts at SV_STRATEGY_DEPLOYER.
contract SharedVaultStrategyDeployer {
  SharedV3Strategy public v3Strategy;
  LpFeeTaker public lpFeeTaker;

  constructor() {
    lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(SV_V3UTILS, address(lpFeeTaker));
  }
}

/// @dev Deploys SharedVault, SharedVaultFactory, SharedConfigManager.
///      Pre-deployed by echidna via deployContracts at SV_CORE_DEPLOYER.
contract SharedVaultCoreDeployer {
  SharedVault public vaultImpl;
  SharedVaultFactory public vaultFactory;
  SharedConfigManager public configManager;

  constructor() {
    configManager = new SharedConfigManager();
    vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
  }
}
