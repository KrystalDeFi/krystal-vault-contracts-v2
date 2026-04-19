// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedVaultFactory } from "../../contracts/shared-vault/interfaces/ISharedVaultFactory.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Withdrawable } from "../../contracts/common/Withdrawable.sol";

/// @dev Mock strategy that returns a PositionChange so vault execution is observable via getPositionCount()
contract MockFactoryStrategy is ISharedStrategy {
  // nfpm address used for all mock positions — unique tokenIds distinguish each call
  address public constant MOCK_NFPM = address(0xBEEF);

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    uint256 tokenId = abi.decode(data, (uint256));
    if (tokenId == 0) return new PositionChange[](0);
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, MOCK_NFPM, tokenId, address(0), address(0));
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override {}
}

// Mock WETH9 for testing native ETH wrapping/unwrapping
contract MockWETH9 {
  string public name = "Wrapped Ether";
  string public symbol = "WETH";
  uint8 public decimals = 18;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  receive() external payable {
    deposit();
  }

  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
  }

  function withdraw(uint256 wad) external {
    require(balanceOf[msg.sender] >= wad, "Insufficient WETH");
    balanceOf[msg.sender] -= wad;
    (bool ok, ) = msg.sender.call{ value: wad }("");
    require(ok, "ETH transfer failed");
  }

  function totalSupply() external view returns (uint256) {
    return address(this).balance;
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
  MockFactoryStrategy public mockStrategy;

  MockERC20 public tokenA;
  MockERC20 public tokenB;
  MockWETH9 public mockWeth;

  address public constant FACTORY_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant VAULT_CREATOR = 0x1234567890123456789012345678901234567891;

  function setUp() public {
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");
    mockWeth = new MockWETH9();
    mockStrategy = new MockFactoryStrategy();

    configManager = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);
    address[] memory callers = new address[](0);
    address[] memory nfpms = new address[](1);
    nfpms[0] = mockStrategy.MOCK_NFPM();
    configManager.initialize(FACTORY_OWNER, targets, callers, FACTORY_OWNER, nfpms, new address[](0));

    vaultImplementation = new SharedVault();

    factory = new SharedVaultFactory();
    factory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation), address(mockWeth));
  }

  function test_createVault_simple() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    tokenB.mint(VAULT_CREATOR, 200e18);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);
    tokenB.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    address vaultAddr = factory.createVault("Test Vault", tokens, amounts);
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

    address vaultAddr = factory.createVault("Empty Vault", tokens, amounts);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    assertEq(IERC20(vaultAddr).totalSupply(), 0);
  }

  function test_createVault_deterministic_address() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vault1 = factory.createVault("Vault 1", tokens, amounts);
    vm.stopPrank();

    assertTrue(vault1 != address(0));

    // Same name + sender should revert with descriptive error
    vm.startPrank(VAULT_CREATOR);
    vm.expectRevert(ISharedVaultFactory.DuplicateVaultName.selector);
    factory.createVault("Vault 1", tokens, amounts);
    vm.stopPrank();
  }

  function test_createVault_multiple_vaults() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vault1 = factory.createVault("Vault A", tokens, amounts);
    address vault2 = factory.createVault("Vault B", tokens, amounts);
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

    factory.createVault("V1", tokens, amounts);
    factory.createVault("V2", tokens, amounts);
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
    factory.createVault("V1", tokens, amounts);
    vm.stopPrank();

    // Unpause
    vm.startPrank(FACTORY_OWNER);
    factory.unpause();
    vm.stopPrank();

    // Should work now
    vm.startPrank(VAULT_CREATOR);
    factory.createVault("V1", tokens, amounts);
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

  // ==================== createVault with execute(actions) ====================

  function test_createVault_with_empty_strategies() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    address vaultAddr = factory.createVault("Test", tokens, amounts, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    assertEq(ISharedVault(vaultAddr).getPositionCount(), 0);
  }

  function test_createVault_with_single_strategy() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    tokenB.mint(VAULT_CREATOR, 200e18);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);
    tokenB.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );

    address vaultAddr = factory.createVault("Test", tokens, amounts, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    // Strategy was called and returned a PositionChange — vault should have tracked it
    assertEq(ISharedVault(vaultAddr).getPositionCount(), 1);

    uint256 expectedInitialShares = SharedVault(payable(vaultAddr)).INITIAL_SHARES();
    assertEq(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), expectedInitialShares);
    assertEq(IERC20(vaultAddr).balanceOf(address(factory)), 0);
  }

  function test_createVault_with_multiple_strategies() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](3);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(2)),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[2] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(3)),
      ISharedCommon.CallType.DELEGATECALL
    );

    address vaultAddr = factory.createVault("Test", tokens, amounts, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    // Each strategy call returned a unique PositionChange — vault tracks all 3
    assertEq(ISharedVault(vaultAddr).getPositionCount(), 3);
  }

  function test_createVault_strategy_not_whitelisted() public {
    address unwhitelisted = address(new MockFactoryStrategy());

    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(unwhitelisted, abi.encode(uint256(0)), ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, unwhitelisted));
    factory.createVault("Test", tokens, amounts, actions);
    vm.stopPrank();
  }

  // ==================== Native ETH / WETH Tests ====================

  /// @notice ETH sent to createVault is wrapped to WETH and deposited into the vault
  function test_createVault_eth_wraps_for_initial_deposit() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    vm.deal(VAULT_CREATOR, 1 ether);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(1 ether), uint256(0), uint256(0)];

    address vaultAddr = factory.createVault{ value: 1 ether }("ETH Vault", tokens, amounts);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    ISharedVault vault = ISharedVault(vaultAddr);

    // Vault holds tokenA and WETH (ETH was wrapped)
    assertEq(tokenA.balanceOf(vaultAddr), 100e18);
    assertEq(mockWeth.balanceOf(vaultAddr), 1 ether);

    // Shares minted to creator
    assertGt(IERC20(vaultAddr).totalSupply(), 0);
    assertGt(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), 0);

    // Vault weth address is set
    assertEq(vault.weth(), address(mockWeth));

    // Creator's ETH is fully consumed
    assertEq(VAULT_CREATOR.balance, 0);
  }

  /// @notice Sending ETH when WETH is not in the token list reverts
  function test_createVault_eth_fails_weth_not_configured() public {
    vm.deal(VAULT_CREATOR, 1 ether);
    vm.startPrank(VAULT_CREATOR);

    // Token list does NOT include mockWeth
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    factory.createVault{ value: 1 ether }("ETH Vault", tokens, amounts);
    vm.stopPrank();
  }

  /// @notice msg.value must equal initialAmounts[wethIndex], otherwise reverts
  function test_createVault_eth_fails_wrong_amount() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    vm.deal(VAULT_CREATOR, 2 ether);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    // initialAmounts[1] = 1 ether but msg.value = 2 ether
    uint256[4] memory amounts = [uint256(100e18), uint256(1 ether), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    factory.createVault{ value: 2 ether }("ETH Vault", tokens, amounts);
    vm.stopPrank();
  }

  /// @notice Batch createVault: msg.value is only used for WETH initial wrap in _createVault, not auto-split to strategy calls
  function test_createVault_strategies_eth_not_for_deposit() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    tokenB.mint(VAULT_CREATOR, 100e18);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);
    tokenB.approve(address(factory), type(uint256).max);

    // Only ERC20 tokens — no WETH in token list
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(0)),
      ISharedCommon.CallType.DELEGATECALL
    );

    address vaultAddr = factory.createVault{ value: 0 }("No-ETH Vault", tokens, amounts, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    // Vault has ERC20 tokens (no WETH)
    assertEq(tokenA.balanceOf(vaultAddr), 100e18);
    assertEq(tokenB.balanceOf(vaultAddr), 100e18);
    assertEq(mockWeth.balanceOf(vaultAddr), 0);

    uint256 expectedInitialShares = SharedVault(payable(vaultAddr)).INITIAL_SHARES();
    assertEq(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), expectedInitialShares);
    assertEq(IERC20(vaultAddr).balanceOf(address(factory)), 0);
  }

  /// @notice Batch createVault: native ETH msg.value must match WETH initial amount; strategies run with callValues from factory balance (zero here)
  function test_createVault_strategies_with_weth_deposit_from_eth() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    vm.deal(VAULT_CREATOR, 1 ether);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(1 ether), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(0)),
      ISharedCommon.CallType.DELEGATECALL
    );

    address vaultAddr = factory.createVault{ value: 1 ether }("ETH-Deposit+Strategy Vault", tokens, amounts, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    assertEq(mockWeth.balanceOf(vaultAddr), 1 ether, "WETH wrapped from ETH deposit");
    assertEq(tokenA.balanceOf(vaultAddr), 100e18, "tokenA transferred as ERC20");
    assertEq(address(factory).balance, 0);

    uint256 expectedInitialShares = SharedVault(payable(vaultAddr)).INITIAL_SHARES();
    assertEq(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), expectedInitialShares);
    assertEq(IERC20(vaultAddr).balanceOf(address(factory)), 0);
  }

  /// @notice When paying WETH initial deposit via msg.value, it must equal initialAmounts[wethIndex] exactly
  function test_createVault_strategies_eth_deposit_fails_wrong_msg_value() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    vm.deal(VAULT_CREATOR, 3 ether);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(1 ether), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(0)),
      ISharedCommon.CallType.DELEGATECALL
    );

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    factory.createVault{ value: 3 ether }("Bad-Total Vault", tokens, amounts, actions);
    vm.stopPrank();
  }

  // ==================== setVaultImplementation zero-address ====================

  function test_setVaultImplementation_fail_zero() public {
    vm.startPrank(FACTORY_OWNER);
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    factory.setVaultImplementation(address(0));
    vm.stopPrank();
  }

  // ==================== Sweep tests (factory inherits Withdrawable) ====================

  function test_sweepNativeToken_success() public {
    vm.deal(address(factory), 1 ether);
    uint256 before = FACTORY_OWNER.balance;

    vm.prank(FACTORY_OWNER);
    factory.sweepNativeToken(1 ether);

    assertEq(FACTORY_OWNER.balance, before + 1 ether);
    assertEq(address(factory).balance, 0);
  }

  function test_sweepNativeToken_partialAmount() public {
    vm.deal(address(factory), 0.5 ether);
    uint256 before = FACTORY_OWNER.balance;

    vm.prank(FACTORY_OWNER);
    factory.sweepNativeToken(1 ether); // request more than balance — sweeps available

    assertEq(FACTORY_OWNER.balance, before + 0.5 ether);
    assertEq(address(factory).balance, 0);
  }

  function test_sweepNativeToken_revertsForNonOwner() public {
    vm.deal(address(factory), 1 ether);

    vm.prank(VAULT_CREATOR);
    vm.expectRevert();
    factory.sweepNativeToken(1 ether);
  }

  function test_sweepERC20_success() public {
    tokenA.mint(address(factory), 1000e18);

    address[] memory tokens = new address[](1);
    tokens[0] = address(tokenA);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1000e18;

    vm.prank(FACTORY_OWNER);
    factory.sweepERC20(tokens, amounts);

    assertEq(tokenA.balanceOf(FACTORY_OWNER), 1000e18);
    assertEq(tokenA.balanceOf(address(factory)), 0);
  }

  function test_sweepERC20_revertsForNonOwner() public {
    tokenA.mint(address(factory), 1000e18);

    address[] memory tokens = new address[](1);
    tokens[0] = address(tokenA);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1000e18;

    vm.prank(VAULT_CREATOR);
    vm.expectRevert();
    factory.sweepERC20(tokens, amounts);
  }

  function test_sweepERC721_success() public {
    MockFactoryERC721 nft = new MockFactoryERC721();
    nft.mint(address(factory), 42);

    address[] memory tokens = new address[](1);
    tokens[0] = address(nft);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 42;

    vm.prank(FACTORY_OWNER);
    factory.sweepERC721(tokens, tokenIds);

    assertEq(nft.ownerOf(42), FACTORY_OWNER);
  }

  function test_sweepERC721_revertsForNonOwner() public {
    MockFactoryERC721 nft = new MockFactoryERC721();
    nft.mint(address(factory), 42);

    address[] memory tokens = new address[](1);
    tokens[0] = address(nft);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 42;

    vm.prank(VAULT_CREATOR);
    vm.expectRevert();
    factory.sweepERC721(tokens, tokenIds);
  }

  function test_sweepERC1155_success() public {
    MockFactoryERC1155 token1155 = new MockFactoryERC1155();
    token1155.mint(address(factory), 1, 100);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100;

    vm.prank(FACTORY_OWNER);
    factory.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(token1155.balanceOf(FACTORY_OWNER, 1), 100);
    assertEq(token1155.balanceOf(address(factory), 1), 0);
  }

  function test_sweepERC1155_revertsForNonOwner() public {
    MockFactoryERC1155 token1155 = new MockFactoryERC1155();
    token1155.mint(address(factory), 1, 100);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100;

    vm.prank(VAULT_CREATOR);
    vm.expectRevert();
    factory.sweepERC1155(tokens, tokenIds, amounts);
  }
}

// ─── Minimal token mocks for sweep tests ──────────────────────────────────

contract MockFactoryERC721 {
  mapping(uint256 => address) private _owners;

  function mint(address to, uint256 tokenId) external {
    _owners[tokenId] = to;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    return _owners[tokenId];
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(_owners[tokenId] == from, "Not owner");
    _owners[tokenId] = to;
  }
}

contract MockFactoryERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 tokenId, uint256 amount) external {
    balanceOf[to][tokenId] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes calldata) external {
    require(balanceOf[from][tokenId] >= amount, "Insufficient");
    balanceOf[from][tokenId] -= amount;
    balanceOf[to][tokenId] += amount;
  }

  function setApprovalForAll(address, bool) external {}
  function isApprovedForAll(address, address) external pure returns (bool) { return false; }
}
