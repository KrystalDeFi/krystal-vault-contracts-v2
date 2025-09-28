// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestCommon, USER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";

contract VaultFactoryTest is TestCommon {
  ConfigManager public configManager;
  Vault public vault;
  LpStrategy public lpStrategy;
  PoolOptimalSwapper public swapper;

  VaultFactory public vaultFactory;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 100 ether);
    vm.deal(USER, 100 ether);

    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = USER;

    configManager = new ConfigManager();
    configManager.initialize(
      USER,
      new address[](0),
      new address[](0),
      whitelistAutomator,
      new address[](0),
      typedTokens,
      typedTokenTypes,
      0,
      0,
      0,
      address(0),
      new address[](0),
      new address[](0),
      new bytes[](0)
    );
    swapper = new PoolOptimalSwapper();
    address[] memory whitelistNfpms = new address[](1);
    whitelistNfpms[0] = address(NFPM);
    LpValidator validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));
    address[] memory strategies = new address[](1);
    strategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(strategies, true);

    vault = new Vault();

    vaultFactory = new VaultFactory();
    vaultFactory.initialize(USER, WETH, address(configManager), address(vault));
  }

  function test_createVault() public {
    console.log("==== test_createVault ====");

    IERC20(WETH).approve(address(vaultFactory), 1 ether);

    // Error pass
    vaultFactory.pause();

    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
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

    Vault vaultInstance = Vault(payable(vaultAddress));

    address vaultOwner = vaultInstance.vaultOwner();
    address vaultConfigManager = address(vaultInstance.configManager());
    (bool allowDeposit, uint8 rangeStrategyType, uint8 tvlStrategyType, address principalToken,,) =
      vaultInstance.getVaultConfig();
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

    assertEq(currentConfigManager, address(configManager));
    assertEq(currentVaultImplementation, address(vault));

    address newConfigManager = USER;
    address newVaultImplementation = USER;

    vaultFactory.setConfigManager(newConfigManager);
    vaultFactory.setVaultImplementation(newVaultImplementation);

    address updatedConfigManager = vaultFactory.configManager();
    address updatedVaultImplementation = vaultFactory.vaultImplementation();

    assertNotEq(updatedConfigManager, currentConfigManager);
    assertNotEq(updatedVaultImplementation, currentVaultImplementation);

    assertEq(updatedConfigManager, newConfigManager);
    assertEq(updatedVaultImplementation, newVaultImplementation);
  }

  function test_createVaultAndAllocate() public {
    console.log("==== test_createVaultAndAllocate ====");

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.8 ether);

    ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
      tickLower: -887_220,
      tickUpper: 887_200,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(params)
    });

    // Prepare VaultCreateParams
    ICommon.VaultCreateParams memory vaultCreateParams = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Allocated Vault",
      symbol: "AV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    // Approve WETH for transfer
    IERC20(WETH).approve(address(vaultFactory), 1 ether);

    // Call createVaultAndAllocate
    address vaultAddress =
      vaultFactory.createVaultAndAllocate(vaultCreateParams, assets, lpStrategy, abi.encode(instruction));

    // Check vault is created and allocated
    address[] memory vaultByUser = new address[](1);
    vaultByUser[0] = vaultFactory.vaultsByAddress(USER, 0);
    address[] memory allVaults = new address[](1);
    allVaults[0] = vaultFactory.allVaults(0);
    assertEq(vaultByUser[0], vaultAddress);
    assertEq(allVaults[0], vaultAddress);

    Vault vaultInstance = Vault(payable(vaultAddress));
    address vaultOwner = vaultInstance.vaultOwner();
    address vaultConfigManager = address(vaultInstance.configManager());
    (bool allowDeposit, uint8 rangeStrategyType, uint8 tvlStrategyType, address principalToken,,) =
      vaultInstance.getVaultConfig();
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: allowDeposit,
      rangeStrategyType: rangeStrategyType,
      tvlStrategyType: tvlStrategyType,
      principalToken: principalToken,
      supportedAddresses: new address[](0)
    });
    AssetLib.Asset[] memory vaultAssets = vaultInstance.getInventory();
    uint256 SHARES_PRECISION = vaultInstance.SHARES_PRECISION();

    // Check ownership and config
    assertEq(vaultOwner, USER);
    assertEq(vaultConfigManager, address(configManager));
    assertEq(vaultConfig.allowDeposit, false);
    assertEq(vaultConfig.rangeStrategyType, 0);
    assertEq(vaultConfig.tvlStrategyType, 0);
    assertEq(vaultConfig.principalToken, WETH);
    assertEq(vaultInstance.balanceOf(USER), 1 ether * SHARES_PRECISION);
    assertEq(vaultAssets.length, 2);
    assertTrue(vaultAssets[0].assetType == AssetLib.AssetType.ERC20);
    assertEq(vaultAssets[0].token, WETH);
    assertApproxEqRel(vaultAssets[0].amount, 0.2 ether, TOLERANCE);
    assertEq(vaultAssets[0].strategy, address(0));
    assertEq(vaultAssets[0].tokenId, 0);
    // Check allocation
    assertTrue(vaultAssets[1].assetType == AssetLib.AssetType.ERC721);
    assertEq(vaultAssets[1].token, address(NFPM));
    assertEq(vaultAssets[1].amount, 1);
    assertEq(vaultAssets[1].strategy, address(lpStrategy));

    uint256 allocatedValue = lpStrategy.valueOf(vaultAssets[1], principalToken);
    assertApproxEqRel(allocatedValue, 0.8 ether, TOLERANCE);
  }

  // ============ IS VAULT OPTIMIZATION TESTS ============

  function test_isVault_optimization_large_number_of_vaults() public {
    console.log("==== test_isVault_optimization_large_number_of_vaults ====");

    // Create multiple vaults to test the optimization
    address[] memory createdVaults = new address[](10);

    for (uint256 i = 0; i < 10; i++) {
      IERC20(WETH).approve(address(vaultFactory), 1 ether);

      ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
        vaultOwnerFeeBasisPoint: 0,
        name: string(abi.encodePacked("Test Vault ", i)),
        symbol: string(abi.encodePacked("TV", i)),
        principalTokenAmount: 1 ether,
        config: ICommon.VaultConfig({
          allowDeposit: false,
          rangeStrategyType: 0,
          tvlStrategyType: 0,
          principalToken: WETH,
          supportedAddresses: new address[](0)
        })
      });

      createdVaults[i] = vaultFactory.createVault(params);
    }

    // Test that all created vaults are recognized
    for (uint256 i = 0; i < 10; i++) {
      assertTrue(vaultFactory.isVault(createdVaults[i]), "Created vault should be recognized");
    }

    // Test that random addresses are not recognized
    address randomAddress1 = address(0x1234567890123456789012345678901234567890);
    address randomAddress2 = address(0x9876543210987654321098765432109876543210);

    assertFalse(vaultFactory.isVault(randomAddress1), "Random address should not be recognized");
    assertFalse(vaultFactory.isVault(randomAddress2), "Random address should not be recognized");
    assertFalse(vaultFactory.isVault(address(0)), "Zero address should not be recognized");
  }

  function test_isVault_optimization_mapping_consistency() public {
    console.log("==== test_isVault_optimization_mapping_consistency ====");

    // Create a vault
    IERC20(WETH).approve(address(vaultFactory), 1 ether);

    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Consistency Test Vault",
      symbol: "CTV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    address vaultAddress = vaultFactory.createVault(params);

    // Test that the mapping is set correctly
    assertTrue(vaultFactory.isVaultAddress(vaultAddress), "isVaultAddress mapping should be set");
    assertTrue(vaultFactory.isVault(vaultAddress), "isVault should return true for created vault");

    // Test that the vault is in allVaults array
    assertEq(vaultFactory.allVaults(0), vaultAddress, "Vault should be in allVaults array");
  }
}
