// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedVaultFactory } from "../../contracts/shared-vault/interfaces/ISharedVaultFactory.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Mock ERC20 token for testing
contract MockERC20 {
  string public name;
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name, string memory _symbol) {
    name = _name;
    symbol = _symbol;
  }

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
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

contract SharedVaultFactoryTest is TestCommon {
  SharedVaultFactory public factory;
  SharedConfigManager public configManager;
  SharedVault public vaultImplementation;

  MockERC20 public tokenA;
  MockERC20 public tokenB;

  address public constant FACTORY_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant VAULT_CREATOR = 0x1234567890123456789012345678901234567891;

  function setUp() public {
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");

    configManager = new SharedConfigManager();
    address[] memory targets = new address[](0);
    address[] memory callers = new address[](0);
    configManager.initialize(FACTORY_OWNER, targets, callers, FACTORY_OWNER);

    vaultImplementation = new SharedVault();

    factory = new SharedVaultFactory();
    factory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation));
  }

  function test_createVault_simple() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    tokenB.mint(VAULT_CREATOR, 200e18);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);
    tokenB.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    address vaultAddr = factory.createVault("Test Vault", "TV", tokens, amounts);
    vm.stopPrank();

    assertTrue(vaultAddr != address(0));
    assertTrue(factory.isVault(vaultAddr));

    ISharedVault vault = ISharedVault(vaultAddr);
    assertEq(vault.vaultOwner(), VAULT_CREATOR);
    assertEq(vault.tokenCount(), 2);
    assertTrue(vault.isVaultToken(address(tokenA)));
    assertTrue(vault.isVaultToken(address(tokenB)));

    // Check initial shares minted
    assertGt(IERC20(vaultAddr).totalSupply(), 0);

    // Check tokens in vault
    assertEq(tokenA.balanceOf(vaultAddr), 100e18);
    assertEq(tokenB.balanceOf(vaultAddr), 200e18);
  }

  function test_createVault_no_initial_deposit() public {
    vm.startPrank(VAULT_CREATOR);

    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vaultAddr = factory.createVault("Empty Vault", "EV", tokens, amounts);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    assertEq(IERC20(vaultAddr).totalSupply(), 0);
  }

  function test_createVault_deterministic_address() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vault1 = factory.createVault("Vault 1", "V1", tokens, amounts);
    vm.stopPrank();

    assertTrue(vault1 != address(0));

    // Same params should revert (deterministic clash)
    vm.startPrank(VAULT_CREATOR);
    vm.expectRevert();
    factory.createVault("Vault 1", "V1", tokens, amounts);
    vm.stopPrank();
  }

  function test_createVault_multiple_vaults() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vault1 = factory.createVault("Vault A", "VA", tokens, amounts);
    address vault2 = factory.createVault("Vault B", "VB", tokens, amounts);
    vm.stopPrank();

    assertTrue(vault1 != vault2);
    assertTrue(factory.isVault(vault1));
    assertTrue(factory.isVault(vault2));
    assertEq(factory.allVaultsLength(), 2);
  }

  function test_getVaultsByAddress() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    factory.createVault("V1", "V1", tokens, amounts);
    factory.createVault("V2", "V2", tokens, amounts);
    vm.stopPrank();

    address[] memory vaults = factory.getVaultsByAddress(VAULT_CREATOR);
    assertEq(vaults.length, 2);
  }

  function test_pause_unpause() public {
    vm.startPrank(FACTORY_OWNER);
    factory.pause();
    vm.stopPrank();

    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
    factory.createVault("V1", "V1", tokens, amounts);
    vm.stopPrank();

    // Unpause
    vm.startPrank(FACTORY_OWNER);
    factory.unpause();
    vm.stopPrank();

    // Should work now
    vm.startPrank(VAULT_CREATOR);
    factory.createVault("V1", "V1", tokens, amounts);
    vm.stopPrank();
  }

  function test_setConfigManager() public {
    address newConfig = address(0x999);
    vm.startPrank(FACTORY_OWNER);
    factory.setConfigManager(newConfig);
    vm.stopPrank();
    assertEq(address(factory.configManager()), newConfig);
  }

  function test_setConfigManager_fail_zero() public {
    vm.startPrank(FACTORY_OWNER);
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    factory.setConfigManager(address(0));
    vm.stopPrank();
  }

  function test_setVaultImplementation() public {
    address newImpl = address(0x888);
    vm.startPrank(FACTORY_OWNER);
    factory.setVaultImplementation(newImpl);
    vm.stopPrank();
    assertEq(factory.vaultImplementation(), newImpl);
  }

  function test_setVaultImplementation_fail_non_owner() public {
    vm.startPrank(VAULT_CREATOR);
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, VAULT_CREATOR));
    factory.setVaultImplementation(address(0x888));
    vm.stopPrank();
  }
}
