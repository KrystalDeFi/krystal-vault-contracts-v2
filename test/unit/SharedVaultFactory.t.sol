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

contract MockNFPM {
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => address) private _token0;
  mapping(uint256 => address) private _token1;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function storeTokens(uint256 tokenId, address t0, address t1) external {
    _token0[tokenId] = t0;
    _token1[tokenId] = t1;
  }

  function getTokens(uint256 tokenId) external view returns (address, address) {
    return (_token0[tokenId], _token1[tokenId]);
  }
}

/// @dev Mock strategy that returns a PositionChange so vault execution is observable via getPositionCount()
contract MockFactoryStrategy is ISharedStrategy {
  // nfpm address used for all mock positions - unique tokenIds distinguish each call
  address public immutable MOCK_NFPM;

  constructor(address mockNfpm) {
    MOCK_NFPM = mockNfpm;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    uint256 tokenId = abi.decode(data, (uint256));
    if (tokenId == 0) return new PositionChange[](0);
    // DELEGATECALL from SharedVault: `address(this)` is the vault. Position adds must use real vault
    // tokens or SharedVault._applyPositionChanges reverts with TokenNotConfigured.
    address[4] memory t = ISharedVault(address(this)).getTokens();
    address t0;
    address t1;
    for (uint256 i; i < 4;) {
      if (t[i] != address(0)) {
        if (t0 == address(0)) {
          t0 = t[i];
        } else {
          t1 = t[i];
          break;
        }
      }
      unchecked {
        ++i;
      }
    }
    MockNFPM(MOCK_NFPM).mint(address(this), tokenId);
    // Store token pair in NFPM so getPositionTokens can return it (canonical-token check).
    MockNFPM(MOCK_NFPM).storeTokens(tokenId, t0, t1);
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, MOCK_NFPM, tokenId, t0, t1);
  }

  function exitProportional(address, uint256, uint256, uint256, uint256, uint256, uint16)
    external
    pure
    override
    returns (PositionChange[] memory changes)
  {
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionAmountsSplit(address, uint256)
    external
    pure
    override
    returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
  {
    return (0, 0, 0, 0);
  }

  function getPositionTokens(address nfpm, uint256 tokenId) external view override returns (address, address) {
    return MockNFPM(nfpm).getTokens(tokenId);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function collectFees(address, uint256, uint16) external override { }
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
    (bool ok,) = msg.sender.call{ value: wad }("");
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

/// @dev Fee-on-transfer token: charges `feeBps` of every transferFrom.
contract MockFOTToken {
  string public name;
  string public symbol;
  uint8 public decimals = 18;
  uint256 public feeBps;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  constructor(string memory _name, string memory _symbol, uint256 _feeBps) {
    name = _name;
    symbol = _symbol;
    feeBps = _feeBps;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    uint256 fee = (amount * feeBps) / 10_000;
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount - fee;
    totalSupply -= fee;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    uint256 fee = (amount * feeBps) / 10_000;
    balanceOf[from] -= amount;
    balanceOf[to] += amount - fee;
    totalSupply -= fee;
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
  MockNFPM public mockNfpm;

  MockERC20 public tokenA;
  MockERC20 public tokenB;
  MockWETH9 public mockWeth;

  address public constant FACTORY_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant VAULT_CREATOR = 0x1234567890123456789012345678901234567891;
  uint256 internal constant TEST_INITIAL_SHARES = 10e18;

  function setUp() public {
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");
    mockWeth = new MockWETH9();
    mockNfpm = new MockNFPM();
    mockStrategy = new MockFactoryStrategy(address(mockNfpm));

    configManager = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(mockStrategy);
    address[] memory callers = new address[](0);
    address[] memory nfpms = new address[](1);
    nfpms[0] = mockStrategy.MOCK_NFPM();
    configManager.initialize(FACTORY_OWNER, targets, callers, FACTORY_OWNER, 0, nfpms, new address[](0), new address[](0));

    vaultImplementation = new SharedVault();

    factory = new SharedVaultFactory();
    factory.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation), address(mockWeth));
  }

  function test_initialize_sets_state() public view {
    assertEq(factory.owner(), FACTORY_OWNER);
    assertEq(address(factory.configManager()), address(configManager));
    assertEq(factory.vaultImplementation(), address(vaultImplementation));
    assertEq(factory.weth(), address(mockWeth));
  }

  function test_initialize_reverts_zero_owner() public {
    SharedVaultFactory fresh = new SharedVaultFactory();
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    fresh.initialize(address(0), address(configManager), address(vaultImplementation), address(mockWeth));
  }

  function test_initialize_reverts_zero_config_manager() public {
    SharedVaultFactory fresh = new SharedVaultFactory();
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    fresh.initialize(FACTORY_OWNER, address(0), address(vaultImplementation), address(mockWeth));
  }

  function test_initialize_reverts_zero_vault_implementation() public {
    SharedVaultFactory fresh = new SharedVaultFactory();
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    fresh.initialize(FACTORY_OWNER, address(configManager), address(0), address(mockWeth));
  }

  function test_initialize_reverts_zero_weth() public {
    SharedVaultFactory fresh = new SharedVaultFactory();
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    fresh.initialize(FACTORY_OWNER, address(configManager), address(vaultImplementation), address(0));
  }

  function test_initialize_reverts_if_called_twice() public {
    vm.expectRevert();
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

    address vaultAddr = factory.createVault("Test Vault", tokens, amounts, 0);
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

    address vaultAddr = factory.createVault("Empty Vault", tokens, amounts, 0);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    assertEq(IERC20(vaultAddr).totalSupply(), 0);
  }

  function test_createVault_deterministic_address() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vault1 = factory.createVault("Vault 1", tokens, amounts, 0);
    vm.stopPrank();

    assertTrue(vault1 != address(0));

    // Same name + sender should revert with descriptive error
    vm.startPrank(VAULT_CREATOR);
    vm.expectRevert(ISharedVaultFactory.DuplicateVaultName.selector);
    factory.createVault("Vault 1", tokens, amounts, 0);
    vm.stopPrank();
  }

  function test_createVault_multiple_vaults() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vault1 = factory.createVault("Vault A", tokens, amounts, 0);
    address vault2 = factory.createVault("Vault B", tokens, amounts, 0);
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

    factory.createVault("V1", tokens, amounts, 0);
    factory.createVault("V2", tokens, amounts, 0);
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
    factory.createVault("V1", tokens, amounts, 0);
    vm.stopPrank();

    // Unpause
    vm.startPrank(FACTORY_OWNER);
    factory.unpause();
    vm.stopPrank();

    // Should work now
    vm.startPrank(VAULT_CREATOR);
    factory.createVault("V1", tokens, amounts, 0);
    vm.stopPrank();
  }

  /// @dev The pause gate must cover BOTH createVault overloads — the actions overload clones and
  ///      executes too, so leaving it open would make the pause switch trivially bypassable.
  function test_pause_blocksCreateVaultWithActions() public {
    vm.prank(FACTORY_OWNER);
    factory.pause();

    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.prank(VAULT_CREATOR);
    vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
    factory.createVault("PausedActions", tokens, amounts, 0, new ISharedVault.Action[](0));
  }

  function test_pause_revertsForNonOwner() public {
    vm.prank(VAULT_CREATOR);
    vm.expectRevert();
    factory.pause();
  }

  function test_unpause_revertsForNonOwner() public {
    vm.prank(FACTORY_OWNER);
    factory.pause();

    vm.prank(VAULT_CREATOR);
    vm.expectRevert();
    factory.unpause();
  }

  /// @dev The CREATE2 salt is keccak(name, sender, "shared-1.0"): the same creator reusing a name
  ///      must hit the predicted-address code check and revert instead of silently redeploying.
  function test_createVault_duplicateNameSameSender_reverts() public {
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_CREATOR);
    factory.createVault("Reused Name", tokens, amounts, 0);
    vm.expectRevert(ISharedVaultFactory.DuplicateVaultName.selector);
    factory.createVault("Reused Name", tokens, amounts, 0);
    vm.stopPrank();
  }

  /// @dev The sender is part of the salt, so the same name from a different creator is a different
  ///      deterministic address and must succeed.
  function test_createVault_sameNameDifferentSender_succeeds() public {
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.prank(VAULT_CREATOR);
    address vault1 = factory.createVault("Shared Name", tokens, amounts, 0);

    vm.prank(FACTORY_OWNER);
    address vault2 = factory.createVault("Shared Name", tokens, amounts, 0);

    assertTrue(vault1 != vault2, "same name from different senders yields distinct vaults");
    assertTrue(factory.isVault(vault1) && factory.isVault(vault2), "both registered");
  }

  function test_createVault_emitsVaultCreated() public {
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    // The vault address (topic 2) is unknown until the clone is deployed; check owner topic + name data.
    vm.expectEmit(true, false, false, true, address(factory));
    emit ISharedVaultFactory.VaultCreated(VAULT_CREATOR, address(0), "Event Vault");

    vm.prank(VAULT_CREATOR);
    factory.createVault("Event Vault", tokens, amounts, 0);
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

  function test_setConfigManager_fail_non_owner() public {
    vm.prank(VAULT_CREATOR);
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, VAULT_CREATOR));
    factory.setConfigManager(address(0x999));
  }

  function test_setConfigManager_emitsEvent() public {
    address newConfig = address(0x999);
    vm.expectEmit(false, false, false, true, address(factory));
    emit ISharedVaultFactory.ConfigManagerSet(newConfig);
    vm.prank(FACTORY_OWNER);
    factory.setConfigManager(newConfig);
  }

  function test_setVaultImplementation_emitsEvent() public {
    address newImpl = address(0x888);
    vm.expectEmit(false, false, false, true, address(factory));
    emit ISharedVaultFactory.VaultImplementationSet(newImpl);
    vm.prank(FACTORY_OWNER);
    factory.setVaultImplementation(newImpl);
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

    address vaultAddr = factory.createVault("Test", tokens, amounts, 0, actions);
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
    actions[0] =
      ISharedVault.Action(address(mockStrategy), abi.encode(uint256(42)), ISharedCommon.CallType.DELEGATECALL);

    address vaultAddr = factory.createVault("Test", tokens, amounts, 0, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    // Strategy was called and returned a PositionChange — vault should have tracked it
    assertEq(ISharedVault(vaultAddr).getPositionCount(), 1);

    uint256 expectedInitialShares = TEST_INITIAL_SHARES;
    assertEq(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), expectedInitialShares);
    assertEq(IERC20(vaultAddr).balanceOf(address(factory)), 0);
  }

  function test_createVault_with_multiple_strategies() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](3);
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(1)), ISharedCommon.CallType.DELEGATECALL);
    actions[1] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(2)), ISharedCommon.CallType.DELEGATECALL);
    actions[2] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(3)), ISharedCommon.CallType.DELEGATECALL);

    address vaultAddr = factory.createVault("Test", tokens, amounts, 0, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    // Each strategy call returned a unique PositionChange — vault tracks all 3
    assertEq(ISharedVault(vaultAddr).getPositionCount(), 3);
  }

  function test_createVault_strategy_not_whitelisted() public {
    address unwhitelisted = address(new MockFactoryStrategy(address(new MockNFPM())));

    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(unwhitelisted, abi.encode(uint256(0)), ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, unwhitelisted));
    factory.createVault("Test", tokens, amounts, 0, actions);
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

    address vaultAddr = factory.createVault{ value: 1 ether }("ETH Vault", tokens, amounts, 0);
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
    factory.createVault{ value: 1 ether }("ETH Vault", tokens, amounts, 0);
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
    factory.createVault{ value: 2 ether }("ETH Vault", tokens, amounts, 0);
    vm.stopPrank();
  }

  /// @notice Batch createVault: msg.value is only used for WETH initial wrap in _createVault, not auto-split to
  /// strategy calls
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
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(0)), ISharedCommon.CallType.DELEGATECALL);

    address vaultAddr = factory.createVault{ value: 0 }("No-ETH Vault", tokens, amounts, 0, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    // Vault has ERC20 tokens (no WETH)
    assertEq(tokenA.balanceOf(vaultAddr), 100e18);
    assertEq(tokenB.balanceOf(vaultAddr), 100e18);
    assertEq(mockWeth.balanceOf(vaultAddr), 0);

    uint256 expectedInitialShares = TEST_INITIAL_SHARES;
    assertEq(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), expectedInitialShares);
    assertEq(IERC20(vaultAddr).balanceOf(address(factory)), 0);
  }

  /// @notice Batch createVault: native ETH msg.value must match WETH initial amount; strategies run with callValues
  /// from factory balance (zero here)
  function test_createVault_strategies_with_weth_deposit_from_eth() public {
    tokenA.mint(VAULT_CREATOR, 100e18);
    vm.deal(VAULT_CREATOR, 1 ether);

    vm.startPrank(VAULT_CREATOR);
    tokenA.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(1 ether), uint256(0), uint256(0)];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(0)), ISharedCommon.CallType.DELEGATECALL);

    address vaultAddr = factory.createVault{ value: 1 ether }("ETH-Deposit+Strategy Vault", tokens, amounts, 0, actions);
    vm.stopPrank();

    assertTrue(factory.isVault(vaultAddr));
    assertEq(mockWeth.balanceOf(vaultAddr), 1 ether, "WETH wrapped from ETH deposit");
    assertEq(tokenA.balanceOf(vaultAddr), 100e18, "tokenA transferred as ERC20");
    assertEq(address(factory).balance, 0);

    uint256 expectedInitialShares = TEST_INITIAL_SHARES;
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
    actions[0] = ISharedVault.Action(address(mockStrategy), abi.encode(uint256(0)), ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    factory.createVault{ value: 3 ether }("Bad-Total Vault", tokens, amounts, 0, actions);
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

  // ==================== vaultOwnerFeeBasisPoint: locked at createVault ====================

  /// @notice The fee bps passed to `createVault` is forwarded verbatim to `SharedVault.initialize`
  ///         and persisted on the vault. This is the user-visible contract the depositor relies on:
  ///         "the fee I saw at creation is the fee that will be applied forever after".
  function test_createVault_forwards_vaultOwnerFeeBasisPoint_to_vault() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    address vaultAddr = factory.createVault("FeeFwd", tokens, amounts, 750);
    vm.stopPrank();

    assertEq(ISharedVault(vaultAddr).vaultOwnerFeeBasisPoint(), 750, "factory forwarded fee to vault");
  }

  /// @notice The fee-with-actions overload also forwards the fee unmodified.
  function test_createVault_withActions_forwards_vaultOwnerFeeBasisPoint_to_vault() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](0);

    address vaultAddr = factory.createVault("FeeFwdActions", tokens, amounts, 4242, actions);
    vm.stopPrank();

    assertEq(ISharedVault(vaultAddr).vaultOwnerFeeBasisPoint(), 4242);
  }

  /// @notice A fee above the 10_000 bps ceiling is rejected at the factory entry point:
  ///         `initialize` reverts and the whole `createVault` transaction bubbles up the error.
  function test_createVault_reverts_when_vaultOwnerFeeBasisPoint_above_max() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.InvalidVaultOwnerFeeBasisPoint.selector);
    factory.createVault("TooHighFee", tokens, amounts, 10_001);
    vm.stopPrank();
  }

  /// @notice Compile-time guarantee: the public interface does not expose any setter for the
  ///         fee. This test documents/locks that at the runtime level — there is no
  ///         `setVaultOwnerFeeBasisPoint(uint16)` selector on the vault.
  function test_sharedVault_has_no_setter_for_vaultOwnerFeeBasisPoint() public {
    vm.startPrank(VAULT_CREATOR);
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    address vaultAddr = factory.createVault("NoSetter", tokens, amounts, 123);
    vm.stopPrank();

    // Selector for `setVaultOwnerFeeBasisPoint(uint16)` — attempting to call it must revert.
    bytes4 legacySelector = bytes4(keccak256("setVaultOwnerFeeBasisPoint(uint16)"));
    (bool ok,) = vaultAddr.call(abi.encodeWithSelector(legacySelector, uint16(500)));
    assertFalse(ok, "legacy setter must not be callable on vault");
    assertEq(ISharedVault(vaultAddr).vaultOwnerFeeBasisPoint(), 123, "fee unchanged by stray call");
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Factory path FOT / short-transfer guard (symmetric to C-5 deposit fix)
  // ════════════════════════════════════════════════════════════════════════════

  function test_createVault_100pctFOT_initialDeposit_reverts() public {
    // Factory calls safeTransferFrom(creator, vault, amount) then vault.initialize(initialAmounts).
    // For a 100% FOT token the transfer delivers 0 to the vault; without the fix, initialize
    // would mint INITIAL_SHARES against a zero balance, bricking all future deposits.
    MockFOTToken fot100 = new MockFOTToken("FOT100", "F100", 10_000);
    fot100.mint(VAULT_CREATOR, 100e18);
    tokenB.mint(VAULT_CREATOR, 100e18);

    vm.startPrank(VAULT_CREATOR);
    fot100.approve(address(factory), type(uint256).max);
    tokenB.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(fot100), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    factory.createVault("FOT100Vault", tokens, amounts, 0);
    vm.stopPrank();
  }

  function test_createVault_partialFOT_initialDeposit_succeeds() public {
    // Partial FOT (2% fee): vault receives 98% of the declared initialAmount.
    // Since balance > 0, initialize must succeed and mint INITIAL_SHARES.
    MockFOTToken fot2 = new MockFOTToken("FOT2", "F2", 200);
    fot2.mint(VAULT_CREATOR, 100e18);
    tokenB.mint(VAULT_CREATOR, 100e18);

    vm.startPrank(VAULT_CREATOR);
    fot2.approve(address(factory), type(uint256).max);
    tokenB.approve(address(factory), type(uint256).max);

    address[4] memory tokens = [address(fot2), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];

    address vaultAddr = factory.createVault("FOT2Vault", tokens, amounts, 0);
    vm.stopPrank();

    uint256 expectedInitialShares = TEST_INITIAL_SHARES;
    assertEq(IERC20(vaultAddr).balanceOf(VAULT_CREATOR), expectedInitialShares, "INITIAL_SHARES minted");
    assertEq(fot2.balanceOf(vaultAddr), 98e18, "vault received 98% of FOT");
    assertEq(tokenB.balanceOf(vaultAddr), 100e18, "tokenB received in full");
  }
}

// ─── Minimal token mocks for sweep tests
// ──────────────────────────────────

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

  function setApprovalForAll(address, bool) external { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}
