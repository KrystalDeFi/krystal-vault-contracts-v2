// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestCommon, USER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";

import {
  INonfungiblePositionManager as INFPM
} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/public-vault/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/public-vault/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { LpValidator } from "../../contracts/public-vault/strategies/lpUniV3/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { LpStrategy } from "../../contracts/public-vault/strategies/lpUniV3/LpStrategy.sol";
import { ILpStrategy } from "../../contracts/public-vault/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/public-vault/interfaces/strategies/ILpValidator.sol";

// Mock ERC20 token for testing
contract MockERC20 {
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    allowance[from][msg.sender] -= amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// Mock ERC721 token for testing
contract MockERC721 {
  mapping(uint256 => address) public ownerOf;
  mapping(address => uint256) public balanceOf;
  mapping(uint256 => address) public getApproved;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function mint(address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == address(0), "Token already exists");
    ownerOf[tokenId] = to;
    balanceOf[to]++;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    require(
      msg.sender == from || getApproved[tokenId] == msg.sender || isApprovedForAll[from][msg.sender], "Not approved"
    );
    ownerOf[tokenId] = to;
    balanceOf[from]--;
    balanceOf[to]++;
  }

  function setApprovalForAll(address operator, bool approved) external {
    isApprovedForAll[msg.sender][operator] = approved;
  }
}

// Mock ERC1155 token for testing
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function mint(address to, uint256 id, uint256 amount) external {
    balanceOf[to][id] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
    require(balanceOf[from][id] >= amount, "Insufficient balance");
    require(msg.sender == from || isApprovedForAll[from][msg.sender], "Not approved");
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;
  }

  function setApprovalForAll(address operator, bool approved) external {
    isApprovedForAll[msg.sender][operator] = approved;
  }
}

contract VaultFactoryTest is TestCommon {
  ConfigManager public configManager;
  Vault public vault;
  LpStrategy public lpStrategy;
  PoolOptimalSwapper public swapper;

  VaultFactory public vaultFactory;

  MockERC20 public mockERC20;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;

  address public constant NON_OWNER = 0x1234567890123456789012345678901234567892;

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

    // Deploy mock contracts
    mockERC20 = new MockERC20();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();

    vm.stopBroadcast();
  }

  function test_createVault() public {
    console.log("==== test_createVault ====");

    vm.startBroadcast(USER);
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

    vm.stopBroadcast();
  }

  function test_updateVaultFactoryConfig() public {
    console.log("==== test_updateVaultFactoryConfig ====");

    address currentConfigManager = vaultFactory.configManager();
    address currentVaultImplementation = vaultFactory.vaultImplementation();

    assertEq(currentConfigManager, address(configManager));
    assertEq(currentVaultImplementation, address(vault));

    address newConfigManager = USER;
    address newVaultImplementation = USER;

    vm.startBroadcast(USER);
    vaultFactory.setConfigManager(newConfigManager);
    vaultFactory.setVaultImplementation(newVaultImplementation);
    vm.stopBroadcast();

    address updatedConfigManager = vaultFactory.configManager();
    address updatedVaultImplementation = vaultFactory.vaultImplementation();

    assertNotEq(updatedConfigManager, currentConfigManager);
    assertNotEq(updatedVaultImplementation, currentVaultImplementation);

    assertEq(updatedConfigManager, newConfigManager);
    assertEq(updatedVaultImplementation, newVaultImplementation);
  }

  function test_createVaultAndAllocate() public {
    console.log("==== test_createVaultAndAllocate ====");

    vm.startBroadcast(USER);

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
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition), params: abi.encode(params)
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

    vm.stopBroadcast();
  }

  // ============ IS VAULT OPTIMIZATION TESTS ============

  function test_isVault_optimization_large_number_of_vaults() public {
    console.log("==== test_isVault_optimization_large_number_of_vaults ====");

    // Create multiple vaults to test the optimization
    address[] memory createdVaults = new address[](10);

    vm.startBroadcast(USER);
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
    vm.stopBroadcast();

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

    vm.startBroadcast(USER);
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
    vm.stopBroadcast();

    // Test that the mapping is set correctly
    assertTrue(vaultFactory.isVaultAddress(vaultAddress), "isVaultAddress mapping should be set");
    assertTrue(vaultFactory.isVault(vaultAddress), "isVault should return true for created vault");

    // Test that the vault is in allVaults array
    assertEq(vaultFactory.allVaults(0), vaultAddress, "Vault should be in allVaults array");
  }

  // ============ SWEEP TESTS ============

  function test_sweepNativeToken_success() public {
    console.log("==== test_sweepNativeToken_success ====");
    uint256 amount = 1 ether;

    // Send native tokens to factory
    vm.deal(address(vaultFactory), amount);

    uint256 ownerBalanceBefore = USER.balance;

    vm.startBroadcast(USER);
    vaultFactory.sweepNativeToken(amount);
    vm.stopBroadcast();

    assertEq(USER.balance, ownerBalanceBefore + amount);
    assertEq(address(vaultFactory).balance, 0);
  }

  function test_sweepNativeToken_partial_amount() public {
    console.log("==== test_sweepNativeToken_partial_amount ====");
    uint256 factoryBalance = 0.5 ether;
    uint256 sweepAmount = 1 ether; // More than balance

    // Send native tokens to factory
    vm.deal(address(vaultFactory), factoryBalance);

    uint256 ownerBalanceBefore = USER.balance;

    vm.startBroadcast(USER);
    vaultFactory.sweepNativeToken(sweepAmount);
    vm.stopBroadcast();

    // Should sweep only the available balance
    assertEq(USER.balance, ownerBalanceBefore + factoryBalance);
    assertEq(address(vaultFactory).balance, 0);
  }

  function test_sweepNativeToken_unauthorized() public {
    console.log("==== test_sweepNativeToken_unauthorized ====");
    uint256 amount = 1 ether;
    vm.deal(address(vaultFactory), amount);

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    vaultFactory.sweepNativeToken(amount);
    vm.stopBroadcast();
  }

  function test_sweepERC20_success() public {
    console.log("==== test_sweepERC20_success ====");
    uint256 amount = 1000;

    // Mint tokens to factory
    mockERC20.mint(address(vaultFactory), amount);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(USER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();

    assertEq(mockERC20.balanceOf(USER), ownerBalanceBefore + amount);
    assertEq(mockERC20.balanceOf(address(vaultFactory)), 0);
  }

  function test_sweepERC20_multiple_tokens() public {
    console.log("==== test_sweepERC20_multiple_tokens ====");
    MockERC20 mockERC20_2 = new MockERC20();
    uint256 amount1 = 1000;
    uint256 amount2 = 2000;

    // Mint tokens to factory
    mockERC20.mint(address(vaultFactory), amount1);
    mockERC20_2.mint(address(vaultFactory), amount2);

    uint256 ownerBalanceBefore1 = mockERC20.balanceOf(USER);
    uint256 ownerBalanceBefore2 = mockERC20_2.balanceOf(USER);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC20);
    tokens[1] = address(mockERC20_2);
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();

    assertEq(mockERC20.balanceOf(USER), ownerBalanceBefore1 + amount1);
    assertEq(mockERC20_2.balanceOf(USER), ownerBalanceBefore2 + amount2);
    assertEq(mockERC20.balanceOf(address(vaultFactory)), 0);
    assertEq(mockERC20_2.balanceOf(address(vaultFactory)), 0);
  }

  function test_sweepERC20_partial_amount() public {
    console.log("==== test_sweepERC20_partial_amount ====");
    uint256 factoryBalance = 500;
    uint256 sweepAmount = 1000; // More than balance

    // Mint tokens to factory
    mockERC20.mint(address(vaultFactory), factoryBalance);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(USER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = sweepAmount;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();

    // Should sweep only the available balance
    assertEq(mockERC20.balanceOf(USER), ownerBalanceBefore + factoryBalance);
    assertEq(mockERC20.balanceOf(address(vaultFactory)), 0);
  }

  function test_sweepERC20_zero_token() public {
    console.log("==== test_sweepERC20_zero_token ====");
    uint256 amount = 1000;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(USER);
    vm.expectRevert("ZeroAddress");
    vaultFactory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();
  }

  function test_sweepERC20_unauthorized() public {
    console.log("==== test_sweepERC20_unauthorized ====");
    uint256 amount = 1000;
    mockERC20.mint(address(vaultFactory), amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    vaultFactory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();
  }

  function test_sweepERC721_success() public {
    console.log("==== test_sweepERC721_success ====");
    uint256 tokenId = 1;

    // Mint NFT to factory
    mockERC721.mint(address(vaultFactory), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();

    assertEq(mockERC721.ownerOf(tokenId), USER);
    assertEq(mockERC721.balanceOf(address(vaultFactory)), 0);
  }

  function test_sweepERC721_multiple_tokens() public {
    console.log("==== test_sweepERC721_multiple_tokens ====");
    uint256 tokenId1 = 1;
    uint256 tokenId2 = 2;

    // Mint NFTs to factory
    mockERC721.mint(address(vaultFactory), tokenId1);
    mockERC721.mint(address(vaultFactory), tokenId2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC721);
    tokens[1] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();

    assertEq(mockERC721.ownerOf(tokenId1), USER);
    assertEq(mockERC721.ownerOf(tokenId2), USER);
    assertEq(mockERC721.balanceOf(address(vaultFactory)), 0);
  }

  function test_sweepERC721_zero_token() public {
    console.log("==== test_sweepERC721_zero_token ====");
    uint256 tokenId = 1;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startBroadcast(USER);
    vm.expectRevert("ZeroAddress");
    vaultFactory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();
  }

  function test_sweepERC721_unauthorized() public {
    console.log("==== test_sweepERC721_unauthorized ====");
    uint256 tokenId = 1;
    mockERC721.mint(address(vaultFactory), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    vaultFactory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();
  }

  function test_sweepERC1155_success() public {
    console.log("==== test_sweepERC1155_success ====");
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint ERC1155 tokens to factory
    mockERC1155.mint(address(vaultFactory), tokenId, amount);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(USER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    assertEq(mockERC1155.balanceOf(USER, tokenId), ownerBalanceBefore + amount);
    assertEq(mockERC1155.balanceOf(address(vaultFactory), tokenId), 0);
  }

  function test_sweepERC1155_multiple_tokens() public {
    console.log("==== test_sweepERC1155_multiple_tokens ====");
    MockERC1155 mockERC1155_2 = new MockERC1155();
    uint256 tokenId1 = 1;
    uint256 tokenId2 = 2;
    uint256 amount1 = 100;
    uint256 amount2 = 200;

    // Mint ERC1155 tokens to factory
    mockERC1155.mint(address(vaultFactory), tokenId1, amount1);
    mockERC1155_2.mint(address(vaultFactory), tokenId2, amount2);

    uint256 ownerBalanceBefore1 = mockERC1155.balanceOf(USER, tokenId1);
    uint256 ownerBalanceBefore2 = mockERC1155_2.balanceOf(USER, tokenId2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC1155);
    tokens[1] = address(mockERC1155_2);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    assertEq(mockERC1155.balanceOf(USER, tokenId1), ownerBalanceBefore1 + amount1);
    assertEq(mockERC1155_2.balanceOf(USER, tokenId2), ownerBalanceBefore2 + amount2);
    assertEq(mockERC1155.balanceOf(address(vaultFactory), tokenId1), 0);
    assertEq(mockERC1155_2.balanceOf(address(vaultFactory), tokenId2), 0);
  }

  function test_sweepERC1155_partial_amount() public {
    console.log("==== test_sweepERC1155_partial_amount ====");
    uint256 tokenId = 1;
    uint256 factoryBalance = 50;
    uint256 sweepAmount = 100; // More than balance

    // Mint ERC1155 tokens to factory
    mockERC1155.mint(address(vaultFactory), tokenId, factoryBalance);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(USER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = sweepAmount;

    vm.startBroadcast(USER);
    vaultFactory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    // Should sweep only the available balance
    assertEq(mockERC1155.balanceOf(USER, tokenId), ownerBalanceBefore + factoryBalance);
    assertEq(mockERC1155.balanceOf(address(vaultFactory), tokenId), 0);
  }

  function test_sweepERC1155_zero_token() public {
    console.log("==== test_sweepERC1155_zero_token ====");
    uint256 tokenId = 1;
    uint256 amount = 100;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(USER);
    vm.expectRevert("ZeroAddress");
    vaultFactory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();
  }

  function test_sweepERC1155_unauthorized() public {
    console.log("==== test_sweepERC1155_unauthorized ====");
    uint256 tokenId = 1;
    uint256 amount = 100;
    mockERC1155.mint(address(vaultFactory), tokenId, amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    vaultFactory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();
  }
}
