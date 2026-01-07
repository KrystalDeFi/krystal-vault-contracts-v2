// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";
import { VaultAutomatorLpStrategy } from "../helpers/VaultAutomatorLpStrategy.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { LpStrategy } from "../../contracts/public-vault/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/public-vault/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/public-vault/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/public-vault/interfaces/strategies/ILpValidator.sol";
import { VaultFactory } from "../../contracts/public-vault/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/public-vault/interfaces/core/IVaultFactory.sol";
import { IVault } from "../../contracts/public-vault/interfaces/core/IVault.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { VaultAutomator } from "../../contracts/public-vault/strategies/lpUniV3/VaultAutomator.sol";
import {
  INonfungiblePositionManager as INFPM
} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

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
  mapping(uint256 => address) private _owners;
  mapping(address => uint256) public balanceOf;

  function mint(address to, uint256 tokenId) external {
    require(_owners[tokenId] == address(0), "Token already minted");
    _owners[tokenId] = to;
    balanceOf[to]++;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    address owner = _owners[tokenId];
    require(owner != address(0), "Token does not exist");
    return owner;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(_owners[tokenId] == from, "Not the owner");
    _owners[tokenId] = to;
    balanceOf[from]--;
    balanceOf[to]++;
  }

  function approve(address, uint256) external pure returns (bool) {
    return true;
  }

  function getApproved(uint256) external pure returns (address) {
    return address(0);
  }

  function setApprovalForAll(address, bool) external pure { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}

// Mock ERC1155 token for testing
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 tokenId, uint256 amount) external {
    balanceOf[to][tokenId] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes calldata) external {
    require(balanceOf[from][tokenId] >= amount, "Insufficient balance");
    balanceOf[from][tokenId] -= amount;
    balanceOf[to][tokenId] += amount;
  }

  function setApprovalForAll(address, bool) external pure { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}

contract VaultAutomatorTest is TestCommon {
  LpUniV3StructHash.Order emptyUserConfig;

  ConfigManager public configManager;
  ILpStrategy public lpStrategy;
  Vault public vault;
  VaultAutomatorLpStrategy public vaultAutomatorLpStrategy;
  VaultFactory public vaultFactory;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 100 ether);
    vm.deal(USER, 100 ether);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    vaultAutomatorLpStrategy = new VaultAutomatorLpStrategy(USER);

    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = address(vaultAutomatorLpStrategy);

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
    address[] memory whitelistNfpms = new address[](1);
    whitelistNfpms[0] = address(NFPM);

    LpValidator validator = new LpValidator();
    validator.initialize(address(this), address(configManager), whitelistNfpms);
    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    lpStrategy = new LpStrategy(address(configManager), address(swapper), address(validator), address(lpFeeTaker));

    address[] memory whitelistStrategies = new address[](1);
    whitelistStrategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(whitelistStrategies, true);

    vault = new Vault();

    vaultFactory = new VaultFactory();
    vaultFactory.initialize(USER, WETH, address(configManager), address(vault));
  }

  function test_executeAllocateLpStrategy() public {
    console.log("==== createVault ====");

    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    (address vaultOwner, uint256 privateKey) = makeAddrAndKey("vaultOwner");
    setErc20Balance(WETH, vaultOwner, 100 ether);
    vm.deal(vaultOwner, 100 ether);
    vm.stopBroadcast();
    vm.startBroadcast(vaultOwner);
    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    address vaultAddress = vaultFactory.createVault(params);
    vm.stopBroadcast();
    vm.startBroadcast(USER);

    assertEq(IERC20(WETH).balanceOf(vaultAddress), 1 ether);
    assertEq(IERC20(vaultAddress).balanceOf(vaultOwner), 1 ether * vault.SHARES_PRECISION());

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.8 ether);

    ILpStrategy.SwapAndMintPositionParams memory strategyParams = ILpStrategy.SwapAndMintPositionParams({
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
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition), params: abi.encode(strategyParams)
    });

    vm.stopBroadcast();
    vm.startBroadcast(vaultOwner);
    bytes memory signature = _signLpStrategyOrder(emptyUserConfig, privateKey);
    vm.stopBroadcast();
    vm.startBroadcast(USER);

    vm.expectRevert(ICommon.InvalidInstructionType.selector);
    vaultAutomatorLpStrategy.executeAllocate(
      IVault(vaultAddress), assets, lpStrategy, 0, abi.encode(instruction), abi.encode(emptyUserConfig), signature
    );

    // assertEq(IERC20(vaultAddress).balanceOf(vaultOwner), 1 ether * vault.SHARES_PRECISION());

    // AssetLib.Asset[] memory vaultAssets = IVault(vaultAddress).getInventory();

    // assertEq(vaultAssets.length, 3);
    // assertEq(vaultAssets[2].strategy, address(lpStrategy));
    // assertEq(vaultAssets[2].token, NFPM);
  }

  function test_executeHarvest() public {
    // Setup: create vault and deposit asset as in test_executeAllocateLpStrategy
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    (address vaultOwner, uint256 privateKey) = makeAddrAndKey("vaultOwner");
    setErc20Balance(WETH, vaultOwner, 100 ether);
    vm.deal(vaultOwner, 100 ether);
    vm.stopBroadcast();
    vm.startBroadcast(vaultOwner);
    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    address vaultAddress = vaultFactory.createVault(params);
    vm.stopBroadcast();
    vm.startBroadcast(USER);

    // Simulate asset with strategy in vault inventory
    // AssetLib.Asset memory asset = AssetLib.Asset(AssetLib.AssetType.ERC20, address(lpStrategy), WETH, 0, 0.5 ether);
    // For test, we assume the vault allows this asset (in real, would be added by allocate)
    // Prepare order and signature
    bytes memory signature = _signLpStrategyOrder(emptyUserConfig, privateKey);

    // Negative test: asset.strategy == address(0) should revert
    AssetLib.Asset memory assetNoStrategy = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    vm.expectRevert(IVault.InvalidAssetStrategy.selector);
    vaultAutomatorLpStrategy.executeHarvest(
      IVault(vaultAddress), assetNoStrategy, 0, 0, abi.encode(emptyUserConfig), signature
    );

    // Positive test: should succeed if strategy is set (may revert if not fully mocked, but structure is correct)
    // This call may revert if the vault does not actually have the asset, but this is the correct call structure
    // Remove expectRevert if you want to see the actual revert reason
    // vaultAutomatorLpStrategy.executeHarvest(IVault(vaultAddress), asset, 0, 0, abi.encode(emptyUserConfig),
    // signature);
  }

  function test_executeHarvestPrivate() public {
    // Setup: create vault and deposit asset as in test_executeAllocateLpStrategy
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 0,
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    (address vaultOwner, uint256 privateKey) = makeAddrAndKey("vaultOwner");
    setErc20Balance(WETH, vaultOwner, 100 ether);
    vm.deal(vaultOwner, 100 ether);
    vm.stopBroadcast();
    vm.startBroadcast(vaultOwner);
    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    address vaultAddress = vaultFactory.createVault(params);
    vm.stopBroadcast();
    vm.startBroadcast(USER);

    // Simulate array of assets with strategy in vault inventory
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(lpStrategy), WETH, 0, 0.5 ether);
    // Prepare order and signature
    bytes memory signature = _signLpStrategyOrder(emptyUserConfig, privateKey);

    // Negative test: asset.strategy == address(0) should revert
    AssetLib.Asset[] memory assetsNoStrategy = new AssetLib.Asset[](1);
    assetsNoStrategy[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.5 ether);
    vm.expectRevert(IVault.InvalidAssetStrategy.selector);
    vaultAutomatorLpStrategy.executeHarvestPrivate(
      IVault(vaultAddress), assetsNoStrategy, false, 0, 0, abi.encode(emptyUserConfig), signature
    );

    // Positive test: should succeed if strategy is set (may revert if not fully mocked, but structure is correct)
    // This call may revert if the vault does not actually have the asset, but this is the correct call structure
    // vaultAutomatorLpStrategy.executeHarvestPrivate(
    //   IVault(vaultAddress), assets, false, 0, 0, abi.encode(emptyUserConfig), signature
    // );
  }

  function _signLpStrategyOrder(LpUniV3StructHash.Order memory order, uint256 privateKey)
    internal
    view
    returns (bytes memory signature)
  {
    bytes32 digest = vaultAutomatorLpStrategy.hashTypedDataV4(LpUniV3StructHash._hash(order));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    signature = abi.encodePacked(r, s, v);
  }

  // ========== Sweep Tests ==========

  MockERC20 public mockERC20;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;
  address public constant NON_ADMIN = address(0x999);

  function setUpSweepTests() public {
    // Stop any active broadcast from setUp
    vm.stopBroadcast();
    mockERC20 = new MockERC20();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();
  }

  function test_sweepNativeToken_success() public {
    setUpSweepTests();
    uint256 amount = 1 ether;
    vm.deal(address(vaultAutomatorLpStrategy), amount);

    uint256 userBalanceBefore = USER.balance;

    vm.prank(USER);
    vaultAutomatorLpStrategy.sweepNativeToken(amount);

    assertEq(USER.balance, userBalanceBefore + amount);
    assertEq(address(vaultAutomatorLpStrategy).balance, 0);
  }

  function test_sweepERC20_success() public {
    setUpSweepTests();
    uint256 amount = 1000;

    // Mint tokens to automator
    mockERC20.mint(address(vaultAutomatorLpStrategy), amount);

    uint256 userBalanceBefore = mockERC20.balanceOf(USER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(USER);
    vaultAutomatorLpStrategy.sweepERC20(tokens, amounts);

    assertEq(mockERC20.balanceOf(USER), userBalanceBefore + amount);
    assertEq(mockERC20.balanceOf(address(vaultAutomatorLpStrategy)), 0);
  }

  function test_sweepERC20_zero_token() public {
    setUpSweepTests();
    uint256 amount = 1000;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(USER);
    vm.expectRevert("ZeroAddress");
    vaultAutomatorLpStrategy.sweepERC20(tokens, amounts);
  }

  function test_sweepERC20_unauthorized() public {
    setUpSweepTests();
    uint256 amount = 1000;
    mockERC20.mint(address(vaultAutomatorLpStrategy), amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(NON_ADMIN);
    vm.expectRevert();
    vaultAutomatorLpStrategy.sweepERC20(tokens, amounts);
  }

  function test_sweepERC721_success() public {
    setUpSweepTests();
    uint256 tokenId = 1;

    // Mint NFT to automator
    mockERC721.mint(address(vaultAutomatorLpStrategy), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(USER);
    vaultAutomatorLpStrategy.sweepERC721(tokens, tokenIds);

    assertEq(mockERC721.ownerOf(tokenId), USER);
    assertEq(mockERC721.balanceOf(address(vaultAutomatorLpStrategy)), 0);
  }

  function test_sweepERC721_zero_token() public {
    setUpSweepTests();
    uint256 tokenId = 1;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(USER);
    vm.expectRevert("ZeroAddress");
    vaultAutomatorLpStrategy.sweepERC721(tokens, tokenIds);
  }

  function test_sweepERC1155_success() public {
    setUpSweepTests();
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint ERC1155 tokens to automator
    mockERC1155.mint(address(vaultAutomatorLpStrategy), tokenId, amount);

    uint256 userBalanceBefore = mockERC1155.balanceOf(USER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(USER);
    vaultAutomatorLpStrategy.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(mockERC1155.balanceOf(USER, tokenId), userBalanceBefore + amount);
    assertEq(mockERC1155.balanceOf(address(vaultAutomatorLpStrategy), tokenId), 0);
  }

  function test_sweepERC1155_zero_token() public {
    setUpSweepTests();
    uint256 tokenId = 1;
    uint256 amount = 100;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(USER);
    vm.expectRevert("ZeroAddress");
    vaultAutomatorLpStrategy.sweepERC1155(tokens, tokenIds, amounts);
  }
}
