// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestCommon, USER, WETH, DAI, USDC } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { VaultAutomator } from "../../contracts/core/VaultAutomator.sol";

contract VaultFactoryTest is TestCommon {
  ConfigManager public configManager;
  Vault public vault;
  VaultAutomator public vaultAutomator;

  VaultFactory public vaultFactory;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 100 ether);
    vm.deal(USER, 100 ether);

    address[] memory stableTokens = new address[](2);
    stableTokens[0] = DAI;
    stableTokens[1] = USDC;

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    configManager = new ConfigManager(stableTokens, whitelistAutomator);

    vault = new Vault();
    vaultAutomator = new VaultAutomator();

    vaultFactory = new VaultFactory(WETH, address(configManager), address(vault), USER, 1000);
  }

  function test_createVault() public {
    console.log("==== test_createVault ====");

    IERC20(WETH).approve(address(vaultFactory), 1 ether);

    // Error pass
    vaultFactory.pause();

    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      ownerFeeBasisPoint: 2000,
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: DAI,
        supportedAddresses: new address[](0)
      })
    });

    assertTrue(vaultFactory.paused());
    vm.expectRevert(Pausable.EnforcedPause.selector);
    vaultFactory.createVault(params);

    vaultFactory.unpause();

    vm.expectRevert(IVaultFactory.InvalidOwnerFee.selector);
    vaultFactory.createVault(params);

    params.ownerFeeBasisPoint = 1000;

    vm.expectRevert(IVaultFactory.InvalidPrincipalToken.selector);
    vaultFactory.createVault{ value: 1 ether }(params);

    params.config.principalToken = WETH;

    /// Happy pass
    address vaultAddress = vaultFactory.createVault(params);

    address[] memory vaultByUser = new address[](1);
    vaultByUser[0] = vaultFactory.vaultsByAddress(USER, 0);

    address[] memory allVaults = new address[](1);
    allVaults[0] = vaultFactory.allVaults(0);

    assertEq(vaultByUser[0], vaultAddress);
    assertEq(allVaults[0], vaultAddress);

    Vault vaultInstance = Vault(vaultAddress);

    address vaultOwner = vaultInstance.vaultOwner();
    address vaultConfigManager = address(vaultInstance.configManager());
    (bool allowDeposit, uint8 rangeStrategyType, uint8 tvlStrategyType, address principalToken) =
      vaultInstance.vaultConfig();
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: allowDeposit,
      rangeStrategyType: rangeStrategyType,
      tvlStrategyType: tvlStrategyType,
      principalToken: principalToken,
      supportedAddresses: new address[](0)
    });
    AssetLib.Asset[] memory assets = vaultInstance.getInventory();

    AssetLib.Asset memory firstAsset = assets[0];

    uint256 SHARES_PRECISION = vaultInstance.SHARES_PRECISION();

    assertEq(vaultOwner, USER);
    assertEq(vaultConfigManager, address(configManager));
    assertEq(vaultConfig.allowDeposit, false);
    assertEq(vaultConfig.rangeStrategyType, 0);
    assertEq(vaultConfig.tvlStrategyType, 0);
    assertEq(vaultConfig.principalToken, WETH);
    assertEq(vaultInstance.balanceOf(USER), 1 ether * SHARES_PRECISION);
    assertEq(assets.length, 1);
    assertTrue(firstAsset.assetType == AssetLib.AssetType.ERC20);
    assertEq(firstAsset.token, WETH);
    assertEq(firstAsset.amount, 1 ether);
    assertEq(firstAsset.strategy, address(0));
    assertEq(firstAsset.tokenId, 0);
  }

  function test_updateVaultFactoryConfig() public {
    console.log("==== test_updateVaultFactoryConfig ====");

    address currentConfigManager = vaultFactory.configManager();
    address currentVaultImplementation = vaultFactory.vaultImplementation();
    address currentPlatformFeeRecipient = vaultFactory.platformFeeRecipient();
    uint16 currentPlatformFeeBasisPoint = vaultFactory.platformFeeBasisPoint();

    assertEq(currentConfigManager, address(configManager));
    assertEq(currentVaultImplementation, address(vault));
    assertEq(currentPlatformFeeRecipient, USER);
    assertEq(currentPlatformFeeBasisPoint, 1000);

    address newConfigManager = USER;
    address newVaultImplementation = USER;
    address newPlatformFeeRecipient = DAI;
    uint16 newPlatformFeeBasisPoint = 2000;

    vaultFactory.setConfigManager(newConfigManager);
    vaultFactory.setVaultImplementation(newVaultImplementation);
    vaultFactory.setPlatformFeeRecipient(newPlatformFeeRecipient);
    vaultFactory.setPlatformFeeBasisPoint(newPlatformFeeBasisPoint);

    address updatedConfigManager = vaultFactory.configManager();
    address updatedVaultImplementation = vaultFactory.vaultImplementation();
    address updatedPlatformFeeRecipient = vaultFactory.platformFeeRecipient();
    uint16 updatedPlatformFeeBasisPoint = vaultFactory.platformFeeBasisPoint();

    assertNotEq(updatedConfigManager, currentConfigManager);
    assertNotEq(updatedVaultImplementation, currentVaultImplementation);
    assertNotEq(updatedPlatformFeeRecipient, currentPlatformFeeRecipient);
    assertNotEq(updatedPlatformFeeBasisPoint, currentPlatformFeeBasisPoint);

    assertEq(updatedConfigManager, newConfigManager);
    assertEq(updatedVaultImplementation, newVaultImplementation);
    assertEq(updatedPlatformFeeRecipient, newPlatformFeeRecipient);
    assertEq(updatedPlatformFeeBasisPoint, newPlatformFeeBasisPoint);
  }
}
