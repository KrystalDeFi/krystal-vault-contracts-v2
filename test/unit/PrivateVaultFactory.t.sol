// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { PrivateVaultFactory } from "../../contracts/private-vault/core/PrivateVaultFactory.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVaultFactory } from "../../contracts/private-vault/interfaces/core/IPrivateVaultFactory.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateConfigManager } from "../../contracts/private-vault/interfaces/core/IPrivateConfigManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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

// Mock strategy contract for testing
contract MockStrategy {
  uint256 public value;

  function setValue(uint256 _value) external {
    value = _value;
  }

  function getValue() external view returns (uint256) {
    return value;
  }
}

contract PrivateVaultFactoryTest is TestCommon {
  PrivateVaultFactory public factory;
  PrivateVault public vaultImplementation;
  PrivateConfigManager public configManager;

  address public constant FACTORY_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant VAULT_CREATOR = 0x1234567890123456789012345678901234567891;
  address public constant NON_OWNER = 0x1234567890123456789012345678901234567892;

  MockERC20 public mockERC20;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;
  MockStrategy public mockStrategy;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    // Deploy config manager
    configManager = new PrivateConfigManager();

    // Initialize config manager
    address[] memory whitelistTargets = new address[](0);
    address[] memory whitelistCallers = new address[](1);
    whitelistCallers[0] = FACTORY_OWNER;

    configManager.initialize(FACTORY_OWNER, whitelistTargets, whitelistCallers, FACTORY_OWNER);

    // Deploy mock contracts
    mockERC20 = new MockERC20();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();
    mockStrategy = new MockStrategy();

    // Deploy vault implementation
    vaultImplementation = new PrivateVault();

    // Deploy factory
    factory = new PrivateVaultFactory();
    factory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation));

    // Whitelist the mock strategy
    vm.startPrank(FACTORY_OWNER);
    address[] memory strategies = new address[](1);
    strategies[0] = address(mockStrategy);
    configManager.setWhitelistTargets(strategies, true);
    vm.stopPrank();
  }

  // ============ INITIALIZATION TESTS ============

  function test_initialize_success() public {
    PrivateVaultFactory newFactory = new PrivateVaultFactory();

    vm.startBroadcast(FACTORY_OWNER);
    newFactory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation));
    vm.stopBroadcast();

    assertEq(newFactory.owner(), FACTORY_OWNER);
    assertEq(newFactory.configManager(), address(configManager));
    assertEq(newFactory.vaultImplementation(), address(vaultImplementation));
  }

  function test_initialize_zero_owner() public {
    PrivateVaultFactory newFactory = new PrivateVaultFactory();

    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    newFactory.initialize(address(0), address(configManager), address(vaultImplementation));
  }

  function test_initialize_zero_config_manager() public {
    PrivateVaultFactory newFactory = new PrivateVaultFactory();

    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    newFactory.initialize(FACTORY_OWNER, address(0), address(vaultImplementation));
  }

  function test_initialize_zero_vault_implementation() public {
    PrivateVaultFactory newFactory = new PrivateVaultFactory();

    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    newFactory.initialize(FACTORY_OWNER, address(configManager), address(0));
  }

  function test_initialize_already_initialized() public {
    PrivateVaultFactory newFactory = new PrivateVaultFactory();

    vm.startBroadcast(FACTORY_OWNER);
    newFactory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation));

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    newFactory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation));
    vm.stopBroadcast();
  }

  // ============ CREATE VAULT TESTS ============

  function test_createVault_basic() public {
    string memory name = "test-vault";

    vm.startBroadcast(VAULT_CREATOR);

    address vault = factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Verify vault was created
    assertTrue(vault != address(0));
    assertTrue(factory.isVault(vault));

    // Verify vault initialization
    PrivateVault vaultContract = PrivateVault(payable(vault));
    assertEq(vaultContract.vaultOwner(), VAULT_CREATOR);
    // assertEq(address(vaultContract.configManager()), address(configManager));
  }

  function test_createVault_with_native_tokens() public {
    string memory name = "test-vault-native";
    uint256 nativeAmount = 1 ether;

    vm.deal(VAULT_CREATOR, nativeAmount);

    vm.startBroadcast(VAULT_CREATOR);

    address vault = factory.createVault{ value: nativeAmount }(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Verify native tokens were sent to vault
    assertEq(address(vault).balance, nativeAmount);
  }

  function test_createVault_with_erc20_tokens() public {
    string memory name = "test-vault-erc20";
    uint256 tokenAmount = 1000;

    // Set ERC20 balance for creator and approve factory
    setErc20Balance(address(mockERC20), VAULT_CREATOR, tokenAmount);

    vm.startBroadcast(VAULT_CREATOR);
    mockERC20.approve(address(factory), tokenAmount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = tokenAmount;

    address vault = factory.createVault(
      name,
      tokens,
      amounts,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Verify tokens were transferred to vault
    assertEq(mockERC20.balanceOf(vault), tokenAmount);
    assertEq(mockERC20.balanceOf(VAULT_CREATOR), 0);
  }

  function test_createVault_with_erc721_tokens() public {
    string memory name = "test-vault-erc721";
    uint256 tokenId = 1;

    // Mint NFT to creator and approve factory
    mockERC721.mint(VAULT_CREATOR, tokenId);

    vm.startBroadcast(VAULT_CREATOR);
    mockERC721.setApprovalForAll(address(factory), true);

    address[] memory nfts721 = new address[](1);
    nfts721[0] = address(mockERC721);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    address vault = factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      nfts721,
      tokenIds,
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Verify NFT was transferred to vault
    assertEq(mockERC721.ownerOf(tokenId), vault);
  }

  function test_createVault_with_erc1155_tokens() public {
    string memory name = "test-vault-erc1155";
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint ERC1155 tokens to creator and approve factory
    mockERC1155.mint(VAULT_CREATOR, tokenId, amount);

    vm.startBroadcast(VAULT_CREATOR);
    mockERC1155.setApprovalForAll(address(factory), true);

    address[] memory nfts1155 = new address[](1);
    nfts1155[0] = address(mockERC1155);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    address vault = factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      nfts1155,
      tokenIds,
      amounts,
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Verify ERC1155 tokens were transferred to vault
    assertEq(mockERC1155.balanceOf(vault, tokenId), amount);
    assertEq(mockERC1155.balanceOf(VAULT_CREATOR, tokenId), 0);
  }

  function test_createVault_with_multicall() public {
    string memory name = "test-vault-multicall";

    vm.startBroadcast(VAULT_CREATOR);

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 42);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      targets,
      callValues,
      data,
      callTypes
    );

    vm.stopBroadcast();

    // Verify multicall was executed
    assertEq(mockStrategy.getValue(), 42);
  }

  function test_createVault_comprehensive() public {
    string memory name = "test-vault-comprehensive";
    uint256 nativeAmount = 0.5 ether;
    uint256 tokenAmount = 1000;
    uint256 nftId = 1;
    uint256 erc1155Id = 1;
    uint256 erc1155Amount = 50;

    // Setup tokens
    vm.deal(VAULT_CREATOR, nativeAmount);
    setErc20Balance(address(mockERC20), VAULT_CREATOR, tokenAmount);
    mockERC721.mint(VAULT_CREATOR, nftId);
    mockERC1155.mint(VAULT_CREATOR, erc1155Id, erc1155Amount);

    vm.startBroadcast(VAULT_CREATOR);

    // Approve factory for token transfers
    mockERC20.approve(address(factory), tokenAmount);
    mockERC721.setApprovalForAll(address(factory), true);
    mockERC1155.setApprovalForAll(address(factory), true);

    // Prepare parameters
    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = tokenAmount;

    address[] memory nfts721 = new address[](1);
    nfts721[0] = address(mockERC721);

    uint256[] memory nftIds = new uint256[](1);
    nftIds[0] = nftId;

    address[] memory nfts1155 = new address[](1);
    nfts1155[0] = address(mockERC1155);

    uint256[] memory erc1155Ids = new uint256[](1);
    erc1155Ids[0] = erc1155Id;

    uint256[] memory erc1155Amounts = new uint256[](1);
    erc1155Amounts[0] = erc1155Amount;

    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);

    uint256[] memory callValues = new uint256[](1);
    callValues[0] = 0;

    bytes[] memory data = new bytes[](1);
    data[0] = abi.encodeWithSelector(MockStrategy.setValue.selector, 999);

    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.CALL;

    address vault = factory.createVault{ value: nativeAmount }(
      name, tokens, amounts, nfts721, nftIds, nfts1155, erc1155Ids, erc1155Amounts, targets, callValues, data, callTypes
    );

    vm.stopBroadcast();

    // Verify all assets were transferred and multicall executed
    assertEq(address(vault).balance, nativeAmount);
    assertEq(mockERC20.balanceOf(vault), tokenAmount);
    assertEq(mockERC721.ownerOf(nftId), vault);
    assertEq(mockERC1155.balanceOf(vault, erc1155Id), erc1155Amount);
    assertEq(mockStrategy.getValue(), 999);
  }

  function test_createVault_deterministic_address() public {
    string memory name = "deterministic-test";

    vm.startBroadcast(VAULT_CREATOR);

    factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Create another vault with same salt and creator should fail
    vm.startBroadcast(VAULT_CREATOR);

    // This should revert because the vault already exists
    vm.expectRevert();
    factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();
  }

  function test_createVault_with_partial_native_tokens() public {
    string memory name = "partial-native";
    uint256 nativeAmount = 0.5 ether;

    vm.deal(VAULT_CREATOR, nativeAmount);

    vm.startBroadcast(VAULT_CREATOR);
    address vault = factory.createVault{ value: nativeAmount }(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();

    // Verify partial native tokens were sent to vault
    assertEq(address(vault).balance, nativeAmount);
  }

  function test_createVault_insufficient_erc20_balance() public {
    string memory name = "insufficient-erc20";
    uint256 tokenAmount = 1000;

    // Set less ERC20 balance than requested
    setErc20Balance(address(mockERC20), VAULT_CREATOR, tokenAmount - 1);

    vm.startBroadcast(VAULT_CREATOR);
    mockERC20.approve(address(factory), tokenAmount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = tokenAmount;

    vm.expectRevert("Insufficient balance");
    factory.createVault(
      name,
      tokens,
      amounts,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();
  }

  function test_createVault_insufficient_erc20_allowance() public {
    string memory name = "insufficient-allowance";
    uint256 tokenAmount = 1000;

    setErc20Balance(address(mockERC20), VAULT_CREATOR, tokenAmount);

    vm.startBroadcast(VAULT_CREATOR);
    // Don't approve enough tokens
    mockERC20.approve(address(factory), tokenAmount - 1);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = tokenAmount;

    vm.expectRevert("Insufficient allowance");
    factory.createVault(
      name,
      tokens,
      amounts,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();
  }

  function test_createVault_erc721_not_owner() public {
    string memory name = "erc721-not-owner";
    uint256 tokenId = 1;

    // Mint NFT to different address
    mockERC721.mint(NON_OWNER, tokenId);

    vm.startBroadcast(VAULT_CREATOR);

    address[] memory nfts721 = new address[](1);
    nfts721[0] = address(mockERC721);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.expectRevert("Not owner");
    factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      nfts721,
      tokenIds,
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();
  }

  function test_createVault_erc1155_insufficient_balance() public {
    string memory name = "erc1155-insufficient";
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint less tokens than requested
    mockERC1155.mint(VAULT_CREATOR, tokenId, amount - 1);

    vm.startBroadcast(VAULT_CREATOR);
    mockERC1155.setApprovalForAll(address(factory), true);

    address[] memory nfts1155 = new address[](1);
    nfts1155[0] = address(mockERC1155);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.expectRevert("Insufficient balance");
    factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      nfts1155,
      tokenIds,
      amounts,
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();
  }

  // ============ PAUSE/UNPAUSE TESTS ============

  function test_pause() public {
    vm.startBroadcast(FACTORY_OWNER);
    factory.pause();
    vm.stopBroadcast();

    assertTrue(factory.paused());
  }

  function test_pause_unauthorized() public {
    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.pause();
    vm.stopBroadcast();
  }

  function test_unpause() public {
    vm.startBroadcast(FACTORY_OWNER);
    factory.pause();
    factory.unpause();
    vm.stopBroadcast();

    assertFalse(factory.paused());
  }

  function test_unpause_unauthorized() public {
    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.unpause();
    vm.stopBroadcast();
  }

  function test_createVault_when_paused() public {
    vm.startBroadcast(FACTORY_OWNER);
    factory.pause();
    vm.stopBroadcast();

    string memory name = "paused-test";

    vm.startBroadcast(VAULT_CREATOR);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();
  }

  // ============ CONFIG MANAGER TESTS ============

  function test_setConfigManager() public {
    PrivateConfigManager newConfigManager = new PrivateConfigManager();

    // Initialize the new config manager
    address[] memory whitelistTargets = new address[](0);
    address[] memory whitelistCallers = new address[](1);
    whitelistCallers[0] = FACTORY_OWNER;

    newConfigManager.initialize(FACTORY_OWNER, whitelistTargets, whitelistCallers, FACTORY_OWNER);

    vm.startBroadcast(FACTORY_OWNER);

    // Check event emission
    vm.expectEmit(true, false, false, false);
    emit IPrivateVaultFactory.ConfigManagerSet(address(newConfigManager));

    factory.setConfigManager(address(newConfigManager));
    vm.stopBroadcast();

    assertEq(factory.configManager(), address(newConfigManager));
  }

  function test_setConfigManager_zero_address() public {
    vm.startBroadcast(FACTORY_OWNER);
    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    factory.setConfigManager(address(0));
    vm.stopBroadcast();
  }

  function test_setConfigManager_unauthorized() public {
    PrivateConfigManager newConfigManager = new PrivateConfigManager();

    // Initialize the new config manager
    address[] memory whitelistTargets = new address[](0);
    address[] memory whitelistCallers = new address[](1);
    whitelistCallers[0] = FACTORY_OWNER;

    newConfigManager.initialize(FACTORY_OWNER, whitelistTargets, whitelistCallers, FACTORY_OWNER);

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.setConfigManager(address(newConfigManager));
    vm.stopBroadcast();
  }

  // ============ VAULT IMPLEMENTATION TESTS ============

  function test_setVaultImplementation() public {
    PrivateVault newImplementation = new PrivateVault();

    vm.startBroadcast(FACTORY_OWNER);

    // Check event emission
    vm.expectEmit(true, false, false, false);
    emit IPrivateVaultFactory.VaultImplementationSet(address(newImplementation));

    factory.setVaultImplementation(address(newImplementation));
    vm.stopBroadcast();

    assertEq(factory.vaultImplementation(), address(newImplementation));
  }

  function test_setVaultImplementation_zero_address() public {
    vm.startBroadcast(FACTORY_OWNER);
    vm.expectRevert(IPrivateCommon.ZeroAddress.selector);
    factory.setVaultImplementation(address(0));
    vm.stopBroadcast();
  }

  function test_setVaultImplementation_unauthorized() public {
    PrivateVault newImplementation = new PrivateVault();

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.setVaultImplementation(address(newImplementation));
    vm.stopBroadcast();
  }

  // ============ IS VAULT TESTS ============

  function test_isVault_true() public {
    string memory name = "is-vault-test";

    vm.startBroadcast(VAULT_CREATOR);
    address vault = factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0), // no callValues
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();

    assertTrue(factory.isVault(vault));
  }

  function test_isVault_false() public view {
    address randomAddress = address(0x1234567890123456789012345678901234567899);
    assertFalse(factory.isVault(randomAddress));
  }

  function test_isVault_multiple_vaults() public {
    string memory name1 = "vault-1";
    string memory name2 = "vault-2";

    vm.startBroadcast(VAULT_CREATOR);

    address vault1 = factory.createVault(
      name1,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    address vault2 = factory.createVault(
      name2,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    assertTrue(factory.isVault(vault1));
    assertTrue(factory.isVault(vault2));
    assertFalse(factory.isVault(address(0x999)));
  }

  // ============ VAULT TRACKING TESTS ============

  function test_vaultsByAddress() public {
    string memory name = "tracking-test";

    vm.startBroadcast(VAULT_CREATOR);
    address vault = factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();

    // Check that vault was added to the mapping
    assertTrue(factory.isVault(vault));
  }

  function test_allVaults() public {
    string memory name1 = "all-vaults-1";
    string memory name2 = "all-vaults-2";

    vm.startBroadcast(VAULT_CREATOR);

    address vault1 = factory.createVault(
      name1,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    address vault2 = factory.createVault(
      name2,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );

    vm.stopBroadcast();

    // Check that both vaults were created
    assertTrue(factory.isVault(vault1));
    assertTrue(factory.isVault(vault2));
  }

  // ============ IS VAULT OPTIMIZATION TESTS ============

  function test_isVault_optimization_large_number_of_vaults() public {
    // Create multiple vaults to test the optimization
    address[] memory createdVaults = new address[](10);

    for (uint256 i = 0; i < 10; i++) {
      string memory name = string(abi.encodePacked("optimization-test-", i));

      vm.startBroadcast(VAULT_CREATOR);
      createdVaults[i] = factory.createVault(
        name,
        new address[](0),
        new uint256[](0),
        new address[](0),
        new uint256[](0),
        new address[](0),
        new uint256[](0),
        new uint256[](0),
        new address[](0),
        new uint256[](0),
        new bytes[](0),
        new IPrivateCommon.CallType[](0)
      );
      vm.stopBroadcast();
    }

    // Test that all created vaults are recognized
    for (uint256 i = 0; i < 10; i++) {
      assertTrue(factory.isVault(createdVaults[i]), "Created vault should be recognized");
    }

    // Test that random addresses are not recognized
    address randomAddress1 = address(0x1234567890123456789012345678901234567890);
    address randomAddress2 = address(0x9876543210987654321098765432109876543210);

    assertFalse(factory.isVault(randomAddress1), "Random address should not be recognized");
    assertFalse(factory.isVault(randomAddress2), "Random address should not be recognized");
    assertFalse(factory.isVault(address(0)), "Zero address should not be recognized");
  }

  function test_isVault_optimization_mapping_consistency() public {
    string memory name = "consistency-test";

    vm.startBroadcast(VAULT_CREATOR);
    address vaultAddress = factory.createVault(
      name,
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new uint256[](0),
      new address[](0),
      new uint256[](0),
      new bytes[](0),
      new IPrivateCommon.CallType[](0)
    );
    vm.stopBroadcast();

    // Test that the mapping is set correctly
    assertTrue(factory.isVaultAddress(vaultAddress), "isVaultAddress mapping should be set");
    assertTrue(factory.isVault(vaultAddress), "isVault should return true for created vault");

    // Test that the vault is in allVaults array
    assertEq(factory.allVaults(0), vaultAddress, "Vault should be in allVaults array");
  }

  function test_isVault_optimization_gas_efficiency() public {
    // This test verifies that the optimization works by creating many vaults
    // and ensuring isVault still works efficiently

    // Create 20 vaults
    address[] memory createdVaults = new address[](20);

    for (uint256 i = 0; i < 20; i++) {
      string memory name = string(abi.encodePacked("gas-test-", i));

      vm.startBroadcast(VAULT_CREATOR);
      createdVaults[i] = factory.createVault(
        name,
        new address[](0),
        new uint256[](0),
        new address[](0),
        new uint256[](0),
        new address[](0),
        new uint256[](0),
        new uint256[](0),
        new address[](0),
        new uint256[](0),
        new bytes[](0),
        new IPrivateCommon.CallType[](0)
      );
      vm.stopBroadcast();
    }

    // Test isVault on all created vaults - this should be O(1) now
    for (uint256 i = 0; i < 20; i++) {
      assertTrue(factory.isVault(createdVaults[i]), "All created vaults should be recognized");
    }

    // Test isVault on non-vault addresses - this should also be O(1)
    for (uint256 i = 0; i < 10; i++) {
      address randomAddress = address(uint160(0x1000 + i));
      assertFalse(factory.isVault(randomAddress), "Random addresses should not be recognized");
    }
  }

  // ============ SWEEP TESTS ============

  function test_sweepNativeToken_success() public {
    uint256 amount = 1 ether;

    // Send native tokens to factory
    vm.deal(address(factory), amount);

    uint256 ownerBalanceBefore = FACTORY_OWNER.balance;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepNativeToken(amount);
    vm.stopBroadcast();

    assertEq(FACTORY_OWNER.balance, ownerBalanceBefore + amount);
    assertEq(address(factory).balance, 0);
  }

  function test_sweepNativeToken_partial_amount() public {
    uint256 factoryBalance = 0.5 ether;
    uint256 sweepAmount = 1 ether; // More than balance

    // Send native tokens to factory
    vm.deal(address(factory), factoryBalance);

    uint256 ownerBalanceBefore = FACTORY_OWNER.balance;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepNativeToken(sweepAmount);
    vm.stopBroadcast();

    // Should sweep only the available balance
    assertEq(FACTORY_OWNER.balance, ownerBalanceBefore + factoryBalance);
    assertEq(address(factory).balance, 0);
  }

  function test_sweepNativeToken_unauthorized() public {
    uint256 amount = 1 ether;
    vm.deal(address(factory), amount);

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.sweepNativeToken(amount);
    vm.stopBroadcast();
  }

  function test_sweepERC20_success() public {
    uint256 amount = 1000;

    // Mint tokens to factory
    mockERC20.mint(address(factory), amount);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(FACTORY_OWNER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();

    assertEq(mockERC20.balanceOf(FACTORY_OWNER), ownerBalanceBefore + amount);
    assertEq(mockERC20.balanceOf(address(factory)), 0);
  }

  function test_sweepERC20_multiple_tokens() public {
    MockERC20 mockERC20_2 = new MockERC20();
    uint256 amount1 = 1000;
    uint256 amount2 = 2000;

    // Mint tokens to factory
    mockERC20.mint(address(factory), amount1);
    mockERC20_2.mint(address(factory), amount2);

    uint256 ownerBalanceBefore1 = mockERC20.balanceOf(FACTORY_OWNER);
    uint256 ownerBalanceBefore2 = mockERC20_2.balanceOf(FACTORY_OWNER);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC20);
    tokens[1] = address(mockERC20_2);
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();

    assertEq(mockERC20.balanceOf(FACTORY_OWNER), ownerBalanceBefore1 + amount1);
    assertEq(mockERC20_2.balanceOf(FACTORY_OWNER), ownerBalanceBefore2 + amount2);
    assertEq(mockERC20.balanceOf(address(factory)), 0);
    assertEq(mockERC20_2.balanceOf(address(factory)), 0);
  }

  function test_sweepERC20_partial_amount() public {
    uint256 factoryBalance = 500;
    uint256 sweepAmount = 1000; // More than balance

    // Mint tokens to factory
    mockERC20.mint(address(factory), factoryBalance);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(FACTORY_OWNER);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = sweepAmount;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();

    // Should sweep only the available balance
    assertEq(mockERC20.balanceOf(FACTORY_OWNER), ownerBalanceBefore + factoryBalance);
    assertEq(mockERC20.balanceOf(address(factory)), 0);
  }

  function test_sweepERC20_zero_token() public {
    uint256 amount = 1000;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(FACTORY_OWNER);
    vm.expectRevert("ZeroAddress");
    factory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();
  }

  function test_sweepERC20_unauthorized() public {
    uint256 amount = 1000;
    mockERC20.mint(address(factory), amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.sweepERC20(tokens, amounts);
    vm.stopBroadcast();
  }

  function test_sweepERC721_success() public {
    uint256 tokenId = 1;

    // Mint NFT to factory
    mockERC721.mint(address(factory), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();

    assertEq(mockERC721.ownerOf(tokenId), FACTORY_OWNER);
    assertEq(mockERC721.balanceOf(address(factory)), 0);
  }

  function test_sweepERC721_multiple_tokens() public {
    uint256 tokenId1 = 1;
    uint256 tokenId2 = 2;

    // Mint NFTs to factory
    mockERC721.mint(address(factory), tokenId1);
    mockERC721.mint(address(factory), tokenId2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC721);
    tokens[1] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();

    assertEq(mockERC721.ownerOf(tokenId1), FACTORY_OWNER);
    assertEq(mockERC721.ownerOf(tokenId2), FACTORY_OWNER);
    assertEq(mockERC721.balanceOf(address(factory)), 0);
  }

  function test_sweepERC721_zero_token() public {
    uint256 tokenId = 1;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startBroadcast(FACTORY_OWNER);
    vm.expectRevert("ZeroAddress");
    factory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();
  }

  function test_sweepERC721_unauthorized() public {
    uint256 tokenId = 1;
    mockERC721.mint(address(factory), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.sweepERC721(tokens, tokenIds);
    vm.stopBroadcast();
  }

  function test_sweepERC1155_success() public {
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint ERC1155 tokens to factory
    mockERC1155.mint(address(factory), tokenId, amount);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(FACTORY_OWNER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    assertEq(mockERC1155.balanceOf(FACTORY_OWNER, tokenId), ownerBalanceBefore + amount);
    assertEq(mockERC1155.balanceOf(address(factory), tokenId), 0);
  }

  function test_sweepERC1155_multiple_tokens() public {
    MockERC1155 mockERC1155_2 = new MockERC1155();
    uint256 tokenId1 = 1;
    uint256 tokenId2 = 2;
    uint256 amount1 = 100;
    uint256 amount2 = 200;

    // Mint ERC1155 tokens to factory
    mockERC1155.mint(address(factory), tokenId1, amount1);
    mockERC1155_2.mint(address(factory), tokenId2, amount2);

    uint256 ownerBalanceBefore1 = mockERC1155.balanceOf(FACTORY_OWNER, tokenId1);
    uint256 ownerBalanceBefore2 = mockERC1155_2.balanceOf(FACTORY_OWNER, tokenId2);

    address[] memory tokens = new address[](2);
    tokens[0] = address(mockERC1155);
    tokens[1] = address(mockERC1155_2);
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount1;
    amounts[1] = amount2;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    assertEq(mockERC1155.balanceOf(FACTORY_OWNER, tokenId1), ownerBalanceBefore1 + amount1);
    assertEq(mockERC1155_2.balanceOf(FACTORY_OWNER, tokenId2), ownerBalanceBefore2 + amount2);
    assertEq(mockERC1155.balanceOf(address(factory), tokenId1), 0);
    assertEq(mockERC1155_2.balanceOf(address(factory), tokenId2), 0);
  }

  function test_sweepERC1155_partial_amount() public {
    uint256 tokenId = 1;
    uint256 factoryBalance = 50;
    uint256 sweepAmount = 100; // More than balance

    // Mint ERC1155 tokens to factory
    mockERC1155.mint(address(factory), tokenId, factoryBalance);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(FACTORY_OWNER, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = sweepAmount;

    vm.startBroadcast(FACTORY_OWNER);
    factory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();

    // Should sweep only the available balance
    assertEq(mockERC1155.balanceOf(FACTORY_OWNER, tokenId), ownerBalanceBefore + factoryBalance);
    assertEq(mockERC1155.balanceOf(address(factory), tokenId), 0);
  }

  function test_sweepERC1155_zero_token() public {
    uint256 tokenId = 1;
    uint256 amount = 100;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(FACTORY_OWNER);
    vm.expectRevert("ZeroAddress");
    factory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();
  }

  function test_sweepERC1155_unauthorized() public {
    uint256 tokenId = 1;
    uint256 amount = 100;
    mockERC1155.mint(address(factory), tokenId, amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.startBroadcast(NON_OWNER);
    vm.expectRevert();
    factory.sweepERC1155(tokens, tokenIds, amounts);
    vm.stopBroadcast();
  }
}
