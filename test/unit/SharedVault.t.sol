// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { Vm } from "forge-std/Vm.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

// Mock strategy that validates tokens and sets a value
contract MockSharedStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    // No state written — this runs via delegatecall; writing to named slots would corrupt vault storage.
    abi.decode(data, (uint256));
    changes = new PositionChange[](0);
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

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override {}
}

// Mock strategy whose exitProportional always reverts (simulates a buggy deployed strategy)
contract MockBrokenExitStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) = abi.decode(
      data,
      (address, uint256, address, address)
    );
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory) {
    revert("broken exit");
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override {}
}

// Mock strategy whose depositProportional always reverts but getPositionAmounts returns non-zero.
// Simulates a rugged pool where the NFPM rejects increaseLiquidity but the strategy still reports liquidity.
contract MockBrokenDepositStrategy is ISharedStrategy {
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) = abi.decode(
      data,
      (address, uint256, address, address)
    );
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
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
    return (100e18, 100e18);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    // Return non-zero so SharedVault computes a non-zero `toAdd` and actually calls depositProportional,
    // which in turn reverts — mirroring the pre-fix behavior of this broken-strategy scenario.
    return (100e18, 100e18);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external pure override {
    revert("pool rugged");
  }
}

// Mock strategy that fails
contract MockFailingStrategy is ISharedStrategy {
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    revert("Strategy failed");
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

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override {}
}

// Mock swap target
contract MockSwapTarget {
  function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
    // Take tokenIn, give tokenOut
    MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    // Give 1:1 swap
    MockERC20(tokenOut).transfer(msg.sender, amountIn);
  }
}

/// @dev Simulates an external contract called via CALL_WITH_POSITIONS that returns PositionChange[].
///      Unlike strategies (which run via delegatecall), this is a standalone contract that the
///      vault calls directly. It mints/burns token approvals and returns position tracking info.
contract MockDirectPositionCreator is ISharedStrategy {
  /// @dev Creates a position: accepts tokens, records LP, returns PositionChange with isAdd=true.
  function createPosition(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1
  ) external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  /// @dev Removes a position: returns PositionChange with isAdd=false.
  function removePosition(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1
  ) external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: false, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  /// @dev Returns an empty PositionChange[] — simulates a no-op call.
  function noChanges() external pure returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  /// @dev Reverts — simulates a failing target call.
  function alwaysFail() external pure returns (PositionChange[] memory) {
    revert("DirectCreator: always fails");
  }

  // ISharedStrategy stubs (not used in CALL_WITH_POSITIONS path)
  function execute(bytes calldata) external payable override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function exitProportional(
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint16
  ) external pure override returns (PositionChange[] memory) {
    return new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256) external pure override returns (uint256, uint256) {
    return (0, 0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override {}
}

// Mock ERC721 for sweep tests
contract MockERC721 {
  mapping(uint256 => address) public ownerOf;
  mapping(uint256 => address) private _approved;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function approve(address spender, uint256 tokenId) external {
    _approved[tokenId] = spender;
  }

  function transferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    require(msg.sender == from || msg.sender == _approved[tokenId], "Not approved");
    ownerOf[tokenId] = to;
    _approved[tokenId] = address(0);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(ownerOf[tokenId] == from, "Not owner");
    ownerOf[tokenId] = to;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
    require(ownerOf[tokenId] == from, "Not owner");
    ownerOf[tokenId] = to;
  }
}

// Mock ERC1155 for sweep tests
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 id, uint256 amount) external {
    balanceOf[to][id] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
    require(balanceOf[from][id] >= amount, "Insufficient balance");
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;
  }
}

// Mock LP pool that holds tokens and simulates proportional LP exits
contract MockLPPool {
  struct LP {
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
  }

  mapping(bytes32 => LP) public lps;

  function deposit(
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    uint256 _amount0,
    uint256 _amount1
  ) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    lp.token0 = token0;
    lp.token1 = token1;
    lp.amount0 += _amount0;
    lp.amount1 += _amount1;
  }

  function exit(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, address recipient) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    LP storage lp = lps[key];
    uint256 exit0 = (lp.amount0 * shares) / totalShares;
    uint256 exit1 = (lp.amount1 * shares) / totalShares;
    if (exit0 > 0) {
      MockERC20(lp.token0).transfer(recipient, exit0);
      lp.amount0 -= exit0;
    }
    if (exit1 > 0) {
      MockERC20(lp.token1).transfer(recipient, exit1);
      lp.amount1 -= exit1;
    }
  }

  function getAmounts(address nfpm, uint256 tokenId) external view returns (uint256, uint256) {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    return (lps[key].amount0, lps[key].amount1);
  }
}

// Mock strategy that simulates realistic LP creation + proportional exits
// Uses immutable lpPool ref so it's accessible in delegatecall context
contract MockLPExitStrategy is ISharedStrategy {
  address public immutable lpPool;

  /// @dev Emitted on proportional exit; under delegatecall this logs from the vault address.
  event ExitVaultOwnerFeeBps(uint16 basisPoints);

  constructor(address _lpPool) {
    lpPool = _lpPool;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1) = abi.decode(
      data,
      (address, uint256, address, address, uint256, uint256)
    );

    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);

    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);

    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16 vaultOwnerFeeBasisPoint
  ) external override returns (PositionChange[] memory changes) {
    emit ExitVaultOwnerFeeBps(vaultOwnerFeeBasisPoint);
    MockLPPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(
    address nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  /// @dev Mock pool doesn't separate principal vs rewards — treat the whole balance as principal.
  ///      Integration coverage for the real split lives in SharedV3/V4/Aerodrome strategy tests.
  function getPositionPrincipalAmounts(
    address nfpm,
    uint256 tokenId
  ) external view override returns (uint256 amount0, uint256 amount1) {
    return MockLPPool(lpPool).getAmounts(nfpm, tokenId);
  }

  function depositProportional(
    address nfpm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16
  ) external override {
    if (amount0 == 0 && amount1 == 0) return;
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address token0, address token1, , ) = MockLPPool(lpPool).lps(key);
    if (amount0 > 0) IERC20(token0).transfer(lpPool, amount0);
    if (amount1 > 0) IERC20(token1).transfer(lpPool, amount1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, amount0, amount1);
  }
}

/// @dev Tracks the last (amount0, amount1) passed to depositProportional through a delegatecall.
///      Used by `MockRewardsAwareStrategy` — the strategy cannot write to its own storage under
///      delegatecall (that would corrupt the vault's storage layout), so it calls out to this tracker.
contract DepositProportionalRecorder {
  uint256 public lastAmount0;
  uint256 public lastAmount1;
  uint16 public lastSlippageBps;
  uint256 public callCount;

  function record(uint256 amount0, uint256 amount1, uint16 slippageBps) external {
    lastAmount0 = amount0;
    lastAmount1 = amount1;
    lastSlippageBps = slippageBps;
    callCount++;
  }
}

/// @dev Mock strategy that mirrors a real Uniswap V3 position with:
///      - a principal (token amounts computed from in-range liquidity at current price), AND
///      - uncollected fees / rewards (tokensOwed).
///
///      `getPositionAmounts` returns `principal + rewards` (total value, used by the vault
///      for share pricing). `getPositionPrincipalAmounts` returns `principal` only (used by
///      the vault when scaling per-depositor top-ups to an existing position).
///
///      `depositProportional` simulates V3's `increaseLiquidity` slippage semantics: when
///      `slippageBps > 0` it reverts with `"OffRatioDeposit"` if the `(amount0, amount1)`
///      ratio diverges from `(principal0, principal1)` beyond the allowed tolerance.
///      This is how the bug manifests in production: mixing rewards into the top-up desired
///      amounts skews the ratio off-range and the pool rejects the slippage check.
contract MockRewardsAwareStrategy is ISharedStrategy {
  DepositProportionalRecorder public immutable recorder;
  address public immutable lpPool;
  uint256 public immutable principal0;
  uint256 public immutable principal1;
  uint256 public immutable rewards0;
  uint256 public immutable rewards1;

  constructor(address _lpPool, address _recorder, uint256 _p0, uint256 _p1, uint256 _r0, uint256 _r1) {
    lpPool = _lpPool;
    recorder = DepositProportionalRecorder(_recorder);
    principal0 = _p0;
    principal1 = _p1;
    rewards0 = _r0;
    rewards1 = _r1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (address nfpm, uint256 tokenId, address token0, address token1) = abi.decode(
      data,
      (address, uint256, address, address)
    );
    // Seed the mock pool with the configured principal amounts so getPositionPrincipalAmounts
    // is consistent with actual pool-side accounting used by exitProportional.
    if (principal0 > 0) IERC20(token0).transfer(lpPool, principal0);
    if (principal1 > 0) IERC20(token1).transfer(lpPool, principal1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, principal0, principal1);
    changes = new PositionChange[](1);
    changes[0] = PositionChange(true, nfpm, tokenId, token0, token1);
  }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16
  ) external override returns (PositionChange[] memory changes) {
    MockLPPool(lpPool).exit(nfpm, tokenId, shares, totalShares, address(this));
    changes = new PositionChange[](0);
  }

  function getPositionAmounts(address, uint256) external view override returns (uint256, uint256) {
    return (principal0 + rewards0, principal1 + rewards1);
  }

  function getPositionPrincipalAmounts(address, uint256) external view override returns (uint256, uint256) {
    return (principal0, principal1);
  }

  /// @dev Simulates Uniswap V3's `increaseLiquidity` behavior when `amount*Min > 0`:
  ///      derives the liquidity that would actually be added (binding side), computes what each
  ///      side would *actually* consume, then reverts if the consumed amount is below amountMin.
  ///      When `slippageBps == 0` it mirrors real V3 by just consuming whatever the pool accepts
  ///      (no revert) — so idle leftovers can be verified by the test.
  function depositProportional(
    address nfpm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16 slippageBps
  ) external override {
    // Record via external CALL (can't use storage under delegatecall without corrupting vault).
    recorder.record(amount0, amount1, slippageBps);
    if (amount0 == 0 && amount1 == 0) return;

    // Compute what Uniswap V3 would actually consume given the current principal ratio.
    // This is the MIN liquidity constraint: L = min(amount0 / factor0, amount1 / factor1),
    // which in our token-amount space reduces to:
    //   consumed0 = min(amount0, amount1 * principal0 / principal1)
    //   consumed1 = min(amount1, amount0 * principal1 / principal0)
    uint256 consumed0 = amount0;
    uint256 consumed1 = amount1;
    if (principal0 > 0 && principal1 > 0) {
      uint256 cap0 = (amount1 * principal0) / principal1;
      uint256 cap1 = (amount0 * principal1) / principal0;
      if (cap0 < consumed0) consumed0 = cap0;
      if (cap1 < consumed1) consumed1 = cap1;
    }

    if (slippageBps > 0) {
      uint256 min0 = (amount0 * (10000 - slippageBps)) / 10000;
      uint256 min1 = (amount1 * (10000 - slippageBps)) / 10000;
      require(consumed0 >= min0 && consumed1 >= min1, "OffRatioDeposit");
    }

    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    (address token0, address token1, , ) = MockLPPool(lpPool).lps(key);
    if (consumed0 > 0) IERC20(token0).transfer(lpPool, consumed0);
    if (consumed1 > 0) IERC20(token1).transfer(lpPool, consumed1);
    MockLPPool(lpPool).deposit(nfpm, tokenId, token0, token1, consumed0, consumed1);
  }
}

contract SharedVaultTest is TestCommon {
  SharedVault public vault;
  SharedConfigManager public configManager;

  MockERC20 public tokenA;
  MockERC20 public tokenB;
  MockERC20 public tokenC;
  MockERC20 public tokenD;
  MockERC20 public tokenE; // non-vault token

  MockSharedStrategy public mockStrategy;
  MockFailingStrategy public failingStrategy;
  MockSwapTarget public swapTarget;
  MockDirectPositionCreator public directCreator;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;
  MockWETH9 public mockWeth;

  address public constant VAULT_OWNER = 0x1234567890123456789012345678901234567890;
  address public constant ADMIN = 0x1234567890123456789012345678901234567891;
  address public constant OPERATOR = 0x1234567890123456789012345678901234567892;
  address public constant DEPOSITOR = 0x1234567890123456789012345678901234567893;
  address public constant NON_AUTHORIZED = 0x1234567890123456789012345678901234567894;

  function setUp() public {
    // Deploy mock tokens
    tokenA = new MockERC20("Token A", "TKA");
    tokenB = new MockERC20("Token B", "TKB");
    tokenC = new MockERC20("Token C", "TKC");
    tokenD = new MockERC20("Token D", "TKD");
    tokenE = new MockERC20("Token E", "TKE");

    // Deploy mock contracts
    mockStrategy = new MockSharedStrategy();
    failingStrategy = new MockFailingStrategy();
    swapTarget = new MockSwapTarget();
    directCreator = new MockDirectPositionCreator();
    mockERC721 = new MockERC721();
    mockERC1155 = new MockERC1155();
    mockWeth = new MockWETH9();

    // Deploy config manager
    configManager = new SharedConfigManager();
    address[] memory targets = new address[](3);
    targets[0] = address(swapTarget);
    targets[1] = address(mockStrategy);
    targets[2] = address(directCreator);
    address[] memory callers = new address[](0);
    configManager.initialize(address(this), targets, callers, address(this), 0, new address[](0), new address[](0));

    // NFPM / swap-router allowlists used by `_addPosition` and `CALL` swap path in unit scenarios
    {
      address[] memory nfpms = new address[](8);
      nfpms[0] = makeAddr("nfpmMigrate");
      nfpms[1] = makeAddr("nfpmNotTracked");
      nfpms[2] = address(0xBEEF);
      nfpms[3] = address(0xBEEF1);
      nfpms[4] = address(0xDEAD);
      nfpms[5] = address(uint160(0xAAAA));
      nfpms[6] = address(uint160(0xBBBB));
      nfpms[7] = makeAddr("nfpm");
      configManager.setWhitelistNfpms(nfpms, true);
    }
    {
      address[] memory routers = new address[](1);
      routers[0] = address(swapTarget);
      configManager.setWhitelistSwapRouters(routers, true);
    }

    // Deploy vault
    vault = new SharedVault();

    // Mint initial tokens and transfer to vault for initialization
    tokenA.mint(address(this), 1000e18);
    tokenB.mint(address(this), 2000e18);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Transfer initial tokens to vault (factory would do this)
    tokenA.transfer(address(vault), 100e18);
    tokenB.transfer(address(vault), 200e18);

    // Initialize: vaultFactory is msg.sender; operator matches factory.owner() (SharedVaultFactory passes owner()).
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initialAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    vault.initialize(
      "Shared Vault",
      vaultTokens,
      initialAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(0)
    );

    // Setup roles
    vault.grantAdminRole(ADMIN);
    vm.stopPrank();
  }

  // ==================== Initialization Tests ====================

  function test_initialize_success() public view {
    assertEq(vault.vaultOwner(), VAULT_OWNER);
    assertEq(vault.tokenCount(), 4);
    assertEq(vault.decimals(), 18);
    assertTrue(vault.isVaultToken(address(tokenA)));
    assertTrue(vault.isVaultToken(address(tokenB)));
    assertTrue(vault.isVaultToken(address(tokenC)));
    assertTrue(vault.isVaultToken(address(tokenD)));
    assertFalse(vault.isVaultToken(address(tokenE)));

    // Initial shares minted to owner: always INITIAL_SHARES on first deposit
    assertEq(vault.balanceOf(VAULT_OWNER), vault.INITIAL_SHARES());
    assertGt(vault.totalSupply(), 0);
  }

  function test_initialize_fail_duplicate_token() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenA), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.DuplicateToken.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0));
  }

  function test_initialize_fail_too_few_tokens() public {
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(0), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.NoTokensConfigured.selector);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, address(0), address(configManager), address(0));
  }

  // ==================== Deposit Tests ====================

  function test_deposit_first() public {
    // Create a fresh vault with no initial deposit
    SharedVault vault2 = new SharedVault();
    address[4] memory tokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    vault2.initialize("Test", tokens, amounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0));
    vm.stopPrank();

    // First deposit
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault2), type(uint256).max);
    tokenB.approve(address(vault2), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault2.deposit(depositAmounts, 0);

    assertEq(shares, vault2.INITIAL_SHARES());
    assertEq(vault2.balanceOf(DEPOSITOR), shares);
    assertEq(tokenA.balanceOf(address(vault2)), 50e18);
    assertEq(tokenB.balanceOf(address(vault2)), 100e18);
    vm.stopPrank();
  }

  function test_deposit_subsequent_proportional() public {
    // Deposit proportionally
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 100e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Current ratio is 100:200 = 1:2, deposit 50:100 maintains ratio
    uint256[4] memory depositAmounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);

    assertGt(shares, 0);
    assertEq(vault.balanceOf(DEPOSITOR), shares);
    vm.stopPrank();
  }

  function test_deposit_excess_capped_at_proportional() public {
    // Vault is 1:2 (100A:200B). User provides 50A + 50B — more A than needed.
    // The minimum-ratio token is B (50/200 < 50/100), so shares are computed from B.
    // The vault takes only the proportional A amount and leaves excess A with the user.
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256 aBalanceBefore = tokenA.balanceOf(DEPOSITOR);

    uint256[4] memory depositAmounts = [uint256(50e18), uint256(50e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);

    assertGt(shares, 0);
    // Only proportional A was taken: 50B / 200B * 100A = 25A
    assertEq(tokenA.balanceOf(DEPOSITOR), aBalanceBefore - 25e18);
    assertEq(tokenB.balanceOf(DEPOSITOR), 0);
    vm.stopPrank();
  }

  function test_deposit_fail_insufficient_token_b() public {
    // User provides correct A but less B than the ratio requires
    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    // Vault is 1:2. Depositing 50A + 50B: min shares come from B (25% of pool),
    // but expectedA for those shares = 25e18. 50A >= 25A so it passes.
    // Now try providing only 1B — min shares from B = 1/200 * totalSupply,
    // expectedA = (1/200 * totalSupply) * 100 / totalSupply = 0.5 → 0 (rounds down).
    // That would succeed, so test a case that truly fails: amounts[i] < expectedAmount.
    // Force fail: provide 0B when B balance is 200e18 (required).
    uint256[4] memory depositAmounts = [uint256(50e18), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    vault.deposit(depositAmounts, 0);
    vm.stopPrank();
  }

  function test_deposit_shares_independent_of_reference_token() public {
    // Regression: the minimum-ratio approach must yield the same shares regardless of which
    // token the caller leads with. Vault is 100A:200B (1:2). Exact proportional 10A:20B.
    tokenA.mint(DEPOSITOR, 10e18);
    tokenB.mint(DEPOSITOR, 20e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256 supplyBefore = vault.totalSupply();
    uint256[4] memory depositAmounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(depositAmounts, 0);
    vm.stopPrank();

    // 10A / 100A == 20B / 200B == 10% of pool → shares = 10% of prior supply
    assertEq(shares, supplyBefore / 10);
    assertEq(tokenA.balanceOf(address(vault)), 110e18);
    assertEq(tokenB.balanceOf(address(vault)), 220e18);
  }

  function test_deposit_fail_invalid_slippage_bps() public {
    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 2e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory depositAmounts = [uint256(1e18), uint256(2e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vault.deposit(depositAmounts, uint16(10001));
    vm.stopPrank();
  }

  // ==================== Withdraw Tests ====================

  function test_withdraw_proportional() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;

    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(halfShares, minAmounts, false);
    vm.stopPrank();

    // Should get ~50% of each token
    assertEq(amounts[0], 50e18);
    assertEq(amounts[1], 100e18);
    assertEq(vault.balanceOf(VAULT_OWNER), ownerShares - halfShares);
  }

  function test_withdraw_all() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory amounts = vault.withdraw(ownerShares, minAmounts, false);
    vm.stopPrank();

    assertEq(amounts[0], 100e18);
    assertEq(amounts[1], 200e18);
    assertEq(vault.balanceOf(VAULT_OWNER), 0);
    assertEq(vault.totalSupply(), 0);
  }

  function test_withdraw_fail_insufficient_shares() public {
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.InsufficientShares.selector);
    vault.withdraw(1, minAmounts, false);
    vm.stopPrank();
  }

  function test_withdraw_fail_min_amounts() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)];

    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InsufficientOutput.selector);
    vault.withdraw(ownerShares, minAmounts, false);
    vm.stopPrank();
  }

  // ==================== Execute Tests ====================

  function test_execute_success() public {
    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_execute_admin() public {
    vm.startPrank(ADMIN);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_execute_fail_unauthorized() public {
    vm.startPrank(NON_AUTHORIZED);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_execute_fail_non_whitelisted_strategy() public {
    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(failingStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.execute(actions);
    vm.stopPrank();
  }

  // ==================== Swap-via-Execute Tests ====================

  function test_swap_success() public {
    // Give swap target some tokenB to return
    tokenB.mint(address(swapTarget), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 9e18, swapCalldata);

    uint256 balanceBefore = tokenB.balanceOf(address(vault));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vault.execute(actions);
    uint256 balanceAfter = tokenB.balanceOf(address(vault));

    assertEq(balanceAfter - balanceBefore, 10e18);
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_in() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenE), address(tokenA), 10e18));
    bytes memory actionData = abi.encode(address(tokenE), address(tokenA), 10e18, 0, swapCalldata);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_swap_fail_non_vault_token_out() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenE), 10e18));
    bytes memory actionData = abi.encode(address(tokenA), address(tokenE), 10e18, 0, swapCalldata);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_swap_fail_non_whitelisted_target() public {
    vm.startPrank(VAULT_OWNER);
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 10e18, 0, "");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(NON_AUTHORIZED, actionData, ISharedCommon.CallType.CALL);
    // `CALL` swap path checks swap-router allowlist before token validation.
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, NON_AUTHORIZED));
    vault.execute(actions);
    vm.stopPrank();
  }

  // ==================== Sweep Tests (factory owner is vault operator) ====================

  function test_sweep_non_vault_token() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(VAULT_OWNER);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();

    assertEq(tokenE.balanceOf(OPERATOR), 100e18);
    assertEq(tokenE.balanceOf(address(vault)), 0);
  }

  function test_sweep_fail_vault_token() public {
    vm.startPrank(VAULT_OWNER);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenA);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 1e18;
    vm.expectRevert(ISharedCommon.CannotSweepVaultToken.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, VAULT_OWNER);
    vm.stopPrank();
  }

  function test_sweep_fail_non_operator() public {
    tokenE.mint(address(vault), 100e18);

    vm.startPrank(OPERATOR);
    address[] memory sweepTokens = new address[](1);
    sweepTokens[0] = address(tokenE);
    uint256[] memory sweepAmounts = new uint256[](1);
    sweepAmounts[0] = 100e18;
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.sweepTokens(sweepTokens, sweepAmounts, OPERATOR);
    vm.stopPrank();
  }

  function test_sweep_native_token() public {
    vm.deal(address(vault), 1 ether);

    vm.startPrank(VAULT_OWNER);
    vault.sweepNativeToken(1 ether, OPERATOR);
    vm.stopPrank();

    assertEq(OPERATOR.balance, 1 ether);
  }

  function test_sweep_erc721() public {
    mockERC721.mint(address(vault), 1);

    vm.startPrank(VAULT_OWNER);
    vault.sweepERC721(address(mockERC721), 1, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC721.ownerOf(1), OPERATOR);
  }

  function test_sweep_erc1155() public {
    mockERC1155.mint(address(vault), 1, 100);

    vm.startPrank(VAULT_OWNER);
    vault.sweepERC1155(address(mockERC1155), 1, 50, OPERATOR);
    vm.stopPrank();

    assertEq(mockERC1155.balanceOf(OPERATOR, 1), 50);
    assertEq(mockERC1155.balanceOf(address(vault), 1), 50);
  }

  // ==================== Role Tests ====================

  function test_grant_revoke_admin() public {
    address newAdmin = address(0x999);
    vm.startPrank(VAULT_OWNER);
    vault.grantAdminRole(newAdmin);
    vm.stopPrank();

    // New admin can execute
    vm.startPrank(newAdmin);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);
    vm.stopPrank();

    // Revoke
    vm.startPrank(VAULT_OWNER);
    vault.revokeAdminRole(newAdmin);
    vm.stopPrank();

    vm.startPrank(newAdmin);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_transfer_ownership() public {
    address newOwner = address(0x777);
    vm.startPrank(VAULT_OWNER);
    vault.transferOwnership(newOwner);
    vm.stopPrank();

    assertEq(vault.vaultOwner(), newOwner);

    // Old owner can't act
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.grantAdminRole(address(0x666));
    vm.stopPrank();
  }

  // ==================== Position Strategy Update via execute() Tests ====================

  function _setupVaultWithBrokenStrategy()
    internal
    returns (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId)
  {
    brokenStrat = new MockBrokenExitStrategy();
    mockNfpm = new MockERC721();
    tokenId = 99;

    // Whitelist the strategy and the mock NFPM
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(brokenStrat);
    configManager.setWhitelistTargets(newTargets, true);
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(mockNfpm);
    configManager.setWhitelistNfpms(newNfpms, true);

    // Mint the position NFT to the vault (simulates the NFPM having issued it)
    mockNfpm.mint(address(vault), tokenId);

    tokenA.mint(DEPOSITOR, 50e18);
    tokenB.mint(DEPOSITOR, 50e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    bytes memory stratData = abi.encode(address(mockNfpm), tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
  }

  // ==================== dropPosition Tests ====================

  function test_dropPosition_happy_path() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    assertEq(vault.getPositionCount(), 1);
    assertEq(mockNfpm.ownerOf(tokenId), address(vault));

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionDropped(VAULT_OWNER, address(mockNfpm), tokenId);
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    // Position removed from tracking and NFT transferred to operator (VAULT_OWNER)
    assertEq(vault.getPositionCount(), 0);
    assertEq(mockNfpm.ownerOf(tokenId), VAULT_OWNER, "NFT should be with operator after drop");
    (brokenStrat);
  }

  function test_dropPosition_unblocks_deposit() public {
    // Deploy a strategy whose getPositionAmounts returns non-zero but depositProportional always reverts.
    // This simulates a rugged pool where the NFPM rejects increaseLiquidity calls.
    MockBrokenDepositStrategy brokenDepStrat = new MockBrokenDepositStrategy();
    address[] memory targets = new address[](1);
    targets[0] = address(brokenDepStrat);
    configManager.setWhitelistTargets(targets, true);

    MockERC721 mockNfpm = new MockERC721();
    uint256 tokenId = 42;
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(mockNfpm);
    configManager.setWhitelistNfpms(newNfpms, true);
    mockNfpm.mint(address(vault), tokenId);

    // Initial deposit so we have a non-zero totalSupply to work against
    tokenA.mint(DEPOSITOR, 300e18);
    tokenB.mint(DEPOSITOR, 300e18);
    vm.prank(DEPOSITOR);
    tokenA.approve(address(vault), 300e18);
    vm.prank(DEPOSITOR);
    tokenB.approve(address(vault), 300e18);
    vm.prank(DEPOSITOR);
    vault.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0);

    // Add the broken position via execute
    bytes memory stratData = abi.encode(address(mockNfpm), tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenDepStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1);

    // Second deposit fails — getPositionAmounts returns non-zero so toAdd > 0, then depositProportional reverts.
    vm.prank(DEPOSITOR);
    vm.expectRevert("pool rugged");
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);

    // Drop the broken position — deposit must succeed afterwards
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);
    assertEq(vault.getPositionCount(), 0);

    vm.prank(DEPOSITOR);
    vault.deposit([uint256(50e18), uint256(50e18), uint256(0), uint256(0)], 0);
  }

  function test_dropPosition_fail_not_tracked() public {
    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vault.dropPosition(address(0xDEAD), 999);
  }

  function test_dropPosition_fail_unauthorized() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.dropPosition(address(mockNfpm), tokenId);
    (brokenStrat);
  }

  function test_dropPosition_keepsNftInVault_whenNoOperator() public {
    // Deploy a fresh vault with operator = address(0) — no operator configured
    SharedVault vaultNoOp = new SharedVault();
    MockERC721 nfpm = new MockERC721();
    uint256 tokenId = 7;

    // Whitelist the nfpm and brokenStrat in configManager (same configManager)
    MockBrokenExitStrategy brokenStrat = new MockBrokenExitStrategy();
    address[] memory newTargets = new address[](1);
    newTargets[0] = address(brokenStrat);
    configManager.setWhitelistTargets(newTargets, true);
    address[] memory newNfpms = new address[](1);
    newNfpms[0] = address(nfpm);
    configManager.setWhitelistNfpms(newNfpms, true);

    // Seed vault with tokens and initialize (operator = address(0))
    tokenA.mint(address(vaultNoOp), 100e18);
    tokenB.mint(address(vaultNoOp), 200e18);
    address[4] memory vaultTokens = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(200e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    vaultNoOp.initialize(
      "No-Op Vault",
      vaultTokens,
      initAmounts,
      VAULT_OWNER,
      address(0),
      address(configManager),
      address(0)
    );

    // Mint the NFT to the vault and add the position
    nfpm.mint(address(vaultNoOp), tokenId);
    bytes memory stratData = abi.encode(address(nfpm), tokenId, address(tokenA), address(tokenB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(brokenStrat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    vaultNoOp.execute(actions);
    assertEq(vaultNoOp.getPositionCount(), 1);

    // Drop the position — no operator, so NFT must stay in vault
    vm.prank(VAULT_OWNER);
    vaultNoOp.dropPosition(address(nfpm), tokenId);

    assertEq(vaultNoOp.getPositionCount(), 0, "position removed from tracking");
    assertEq(nfpm.ownerOf(tokenId), address(vaultNoOp), "NFT stays in vault when no operator");
  }

  // ==================== recoverPosition Tests ====================

  function test_recoverPosition_reAddsPositionToTracking() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();
    address strategy = address(brokenStrat);

    // Drop: NFT goes to operator (VAULT_OWNER)
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);
    assertEq(vault.getPositionCount(), 0);
    assertEq(mockNfpm.ownerOf(tokenId), VAULT_OWNER);

    // Operator approves vault to pull NFT back
    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    // Recover: re-adds position to tracking
    vm.prank(VAULT_OWNER);
    vault.recoverPosition(address(mockNfpm), tokenId, strategy, address(tokenA), address(tokenB));

    assertEq(vault.getPositionCount(), 1, "position back in tracking");
    assertEq(mockNfpm.ownerOf(tokenId), address(vault), "NFT back in vault");
    (address storedStrategy, address storedNfpm, uint256 storedTokenId, , ) = vault.getPosition(0);
    assertEq(storedStrategy, strategy);
    assertEq(storedNfpm, address(mockNfpm));
    assertEq(storedTokenId, tokenId);
  }

  function test_recoverPosition_emitsEvent() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.expectEmit(true, true, true, true);
    emit ISharedVault.PositionRecovered(VAULT_OWNER, address(mockNfpm), tokenId);
    vm.prank(VAULT_OWNER);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_revertsForNonOperator() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_revertsIfTokenNotConfiguredOnVault() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();
    address badToken = address(0xBEEF);

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), badToken, address(tokenB));
  }

  function test_recoverPosition_revertsIfStrategyNotWhitelisted() public {
    (, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    // Use failingStrategy which is not whitelisted in configManager
    vm.prank(VAULT_OWNER);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.recoverPosition(address(mockNfpm), tokenId, address(failingStrategy), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_revertsIfNfpmNotWhitelisted() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);

    // De-whitelist the NFPM after the drop
    address[] memory delistNfpms = new address[](1);
    delistNfpms[0] = address(mockNfpm);
    configManager.setWhitelistNfpms(delistNfpms, false);

    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidNfpm.selector, address(mockNfpm)));
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  function test_recoverPosition_enforcesMaxPositionsLimit() public {
    (MockBrokenExitStrategy brokenStrat, MockERC721 mockNfpm, uint256 tokenId) = _setupVaultWithBrokenStrategy();

    // Drop the position
    vm.prank(VAULT_OWNER);
    vault.dropPosition(address(mockNfpm), tokenId);
    assertEq(vault.getPositionCount(), 0);

    // Fill up to the limit with other positions
    configManager.setMaxPositions(1);
    _addPositionViaDirectCreator(101);
    assertEq(vault.getPositionCount(), 1);

    // Now recover should fail — limit already reached
    vm.prank(VAULT_OWNER);
    mockNfpm.approve(address(vault), tokenId);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.TooManyPositions.selector);
    vault.recoverPosition(address(mockNfpm), tokenId, address(brokenStrat), address(tokenA), address(tokenB));
  }

  // ==================== Pause Tests ====================

  function test_global_pause_blocks_deposit() public {
    configManager.setVaultPaused(true);

    tokenA.mint(DEPOSITOR, 10e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.deposit(amounts, 0);
    vm.stopPrank();
  }

  function test_global_pause_blocks_execute() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_global_pause_blocks_swap() public {
    configManager.setVaultPaused(true);

    vm.startPrank(VAULT_OWNER);
    bytes memory actionData = abi.encode(address(tokenA), address(tokenB), 1e18, 0, "");
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(swapTarget), actionData, ISharedCommon.CallType.CALL);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_per_vault_pause_blocks_deposit() public {
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.stopPrank();

    tokenA.mint(DEPOSITOR, 10e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);

    uint256[4] memory amounts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.deposit(amounts, 0);
    vm.stopPrank();
  }

  function test_per_vault_pause_blocks_execute() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_per_vault_pause_unpause() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(42)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    assertTrue(vault.paused());

    // Unpaused
    vault.setPaused(false);
    assertFalse(vault.paused());

    // Can execute again
    vault.execute(actions);
    vm.stopPrank();
  }

  function test_per_vault_pause_independent_of_global() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(1)),
      ISharedCommon.CallType.DELEGATECALL
    );

    // Per-vault paused, global not paused
    vm.startPrank(VAULT_OWNER);
    vault.setPaused(true);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();

    // Per-vault unpaused, global paused
    vm.prank(VAULT_OWNER);
    vault.setPaused(false);
    configManager.setVaultPaused(true);
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.VaultPaused.selector);
    vault.execute(actions);
    vm.stopPrank();
  }

  // ==================== Vault owner fee + platform fee (LpFeeTaker / config) ====================

  function test_set_platform_fee_basis_point() public {
    // Config manager owner is `address(this)` from setUp `initialize`
    vm.prank(address(this));
    configManager.setPlatformFeeBasisPoint(50);
    assertEq(configManager.platformFeeBasisPoint(), 50);
  }

  function test_set_platform_fee_basis_point_reverts_invalid() public {
    vm.startPrank(address(this));
    vm.expectRevert(ISharedCommon.InvalidFeeBasisPoint.selector);
    configManager.setPlatformFeeBasisPoint(10_001);
    vm.stopPrank();
  }

  function test_set_vault_owner_fee_basis_point() public {
    vm.prank(VAULT_OWNER);
    vault.setVaultOwnerFeeBasisPoint(250);
    assertEq(vault.vaultOwnerFeeBasisPoint(), 250);
  }

  function test_set_vault_owner_fee_basis_point_max() public {
    vm.prank(VAULT_OWNER);
    vault.setVaultOwnerFeeBasisPoint(10_000);
    assertEq(vault.vaultOwnerFeeBasisPoint(), 10_000);
  }

  function test_set_vault_owner_fee_basis_point_reverts_invalid() public {
    vm.startPrank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.InvalidVaultOwnerFeeBasisPoint.selector);
    vault.setVaultOwnerFeeBasisPoint(10_001);
    vm.stopPrank();
  }

  function test_set_vault_owner_fee_basis_point_unauthorized() public {
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.Unauthorized.selector);
    vault.setVaultOwnerFeeBasisPoint(100);
  }

  /// @notice Withdraw delegatecalls `exitProportional` with the stored owner fee bps so strategies can apply performance fees.
  function test_withdraw_forwards_vault_owner_fee_bps_to_strategy() public {
    MockLPPool lpPoolContract = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(lpPoolContract));
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(lpStrategy);
    address[] memory nfpmsFee = new address[](1);
    nfpmsFee[0] = makeAddr("nfpmFee");
    cm.initialize(VAULT_OWNER, targets, new address[](0), address(this), 0, nfpmsFee, new address[](0));

    SharedVault v = new SharedVault();
    MockERC20 tA = new MockERC20("TA", "TA");
    MockERC20 tB = new MockERC20("TB", "TB");
    uint256 dep = 100e18;
    tA.mint(address(this), dep);
    tB.mint(address(this), dep);
    tA.transfer(address(v), dep);
    tB.transfer(address(v), dep);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [dep, dep, uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("FeeBpsVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0));

    vm.prank(VAULT_OWNER);
    v.setVaultOwnerFeeBasisPoint(1234);
    assertEq(v.vaultOwnerFeeBasisPoint(), 1234);

    vm.startPrank(VAULT_OWNER);
    address fakeNfpm = makeAddr("nfpmFee");
    bytes memory stratData = abi.encode(fakeNfpm, uint256(1), address(tA), address(tB), 50e18, 50e18);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    v.execute(actions);
    vm.stopPrank();

    uint256 shares = v.balanceOf(VAULT_OWNER);

    vm.recordLogs();
    vm.prank(VAULT_OWNER);
    v.withdraw(shares, [uint256(0), uint256(0), uint256(0), uint256(0)], false);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    bytes32 evSig = keccak256("ExitVaultOwnerFeeBps(uint16)");
    bool found;
    for (uint256 i; i < logs.length; i++) {
      if (logs[i].emitter == address(v) && logs[i].topics.length > 0 && logs[i].topics[0] == evSig) {
        assertEq(abi.decode(logs[i].data, (uint256)), 1234);
        found = true;
        break;
      }
    }
    assertTrue(found, "ExitVaultOwnerFeeBps must be emitted from vault during delegatecall exit");
  }

  // ==================== Preview Tests ====================

  function test_preview_deposit() public view {
    uint256[4] memory amounts = [uint256(50e18), uint256(100e18), uint256(0), uint256(0)];
    uint256 previewShares = vault.previewDeposit(amounts);
    assertGt(previewShares, 0);
  }

  function test_preview_withdraw() public view {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory previewAmounts = vault.previewWithdraw(ownerShares);
    assertEq(previewAmounts[0], 100e18);
    assertEq(previewAmounts[1], 200e18);
  }

  // ==================== View Tests ====================

  function test_get_tokens() public view {
    address[4] memory vaultTokens = vault.getTokens();
    assertEq(vaultTokens[0], address(tokenA));
    assertEq(vaultTokens[1], address(tokenB));
    assertEq(vaultTokens[2], address(tokenC));
    assertEq(vaultTokens[3], address(tokenD));
  }

  function test_get_idle_balances() public view {
    uint256[4] memory balances = vault.getIdleBalances();
    assertEq(balances[0], 100e18);
    assertEq(balances[1], 200e18);
    assertEq(balances[2], 0);
    assertEq(balances[3], 0);
  }

  // ==================== Native ETH / WETH Tests ====================

  /// @dev Creates a fresh vault with [tokenA, mockWeth] tokens and 100e18 of each.
  ///      ETH is deposited via mockWeth.deposit() so MockWETH9 holds real ETH to back withdrawals.
  function _setupWethVault() internal returns (SharedVault wv) {
    wv = new SharedVault();

    // Wrap 100e18 ETH → WETH; test contract gets the WETH and transfers to vault
    tokenA.mint(address(this), 100e18);
    vm.deal(address(this), 100e18);
    mockWeth.deposit{ value: 100e18 }();

    tokenA.transfer(address(wv), 100e18);
    mockWeth.transfer(address(wv), 100e18);

    address[4] memory wvTokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    wv.initialize(
      "WETH Vault",
      wvTokens,
      initAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(mockWeth)
    );
    vm.stopPrank();
    // VAULT_OWNER now has all shares = 100e18 * SHARES_PRECISION
  }

  /// @notice Depositing with msg.value wraps ETH to WETH inside the vault
  function test_deposit_eth_wraps_to_weth() public {
    SharedVault wethVault = _setupWethVault();

    tokenA.mint(DEPOSITOR, 50e18);
    vm.deal(DEPOSITOR, 50e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(wethVault), type(uint256).max);

    // Deposit 50e18 tokenA + 50e18 ETH (→ WETH). Proportional: 50/100 ratio → exact match.
    uint256[4] memory amounts = [uint256(50e18), uint256(50e18), uint256(0), uint256(0)];
    uint256 shares = wethVault.deposit{ value: 50e18 }(amounts, 0);
    vm.stopPrank();

    assertGt(shares, 0);
    assertEq(wethVault.balanceOf(DEPOSITOR), shares);

    // Vault gained 50e18 WETH from wrapped ETH
    assertEq(mockWeth.balanceOf(address(wethVault)), 150e18);
    // Depositor's ETH is fully consumed
    assertEq(DEPOSITOR.balance, 0);
  }

  /// @notice Proportional deposit: only the needed fraction of WETH is consumed; excess ETH is refunded
  function test_deposit_eth_excess_refund() public {
    SharedVault wethVault = _setupWethVault();
    // State: 100e18 tokenA + 100e18 WETH, totalSupply = 100e18 * SHARES_PRECISION

    // Depositor sends 40e18 tokenA + 80e18 ETH, but the binding constraint is tokenA (40/100 = 40%)
    // transferAmounts = [40e18, 40e18]; excess WETH = 80e18 - 40e18 = 40e18 refunded as ETH
    tokenA.mint(DEPOSITOR, 40e18);
    vm.deal(DEPOSITOR, 80e18);

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(wethVault), type(uint256).max);

    uint256[4] memory amounts = [uint256(40e18), uint256(80e18), uint256(0), uint256(0)];
    wethVault.deposit{ value: 80e18 }(amounts, 0);
    vm.stopPrank();

    // 40e18 ETH refunded; depositor paid net 40e18 ETH
    assertEq(DEPOSITOR.balance, 40e18);
    // Vault received only 40e18 WETH (not 80e18)
    assertEq(mockWeth.balanceOf(address(wethVault)), 140e18);
  }

  /// @notice Sending ETH when no WETH token is configured in the vault reverts
  function test_deposit_eth_fails_weth_not_configured() public {
    // `vault` was initialized with weth = address(0): no WETH slot
    vm.deal(DEPOSITOR, 1 ether);
    uint256[4] memory amounts = [uint256(0), uint256(1 ether), uint256(0), uint256(0)];
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.deposit{ value: 1 ether }(amounts, 0);
  }

  /// @notice msg.value must equal amounts[wethIndex]; mismatch reverts
  function test_deposit_eth_fails_wrong_amount() public {
    SharedVault wethVault = _setupWethVault();
    vm.deal(DEPOSITOR, 60e18);

    uint256[4] memory amounts = [uint256(0), uint256(50e18), uint256(0), uint256(0)];
    vm.prank(DEPOSITOR);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    // msg.value (60e18) != amounts[wethIndex] (50e18)
    wethVault.deposit{ value: 60e18 }(amounts, 0);
  }

  /// @notice Withdraw with unwrap=true: WETH is unwrapped and caller receives native ETH
  function test_withdraw_unwrap_true_sends_native_eth() public {
    SharedVault wethVault = _setupWethVault();
    uint256 shares = wethVault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    uint256 ethBefore = VAULT_OWNER.balance;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = wethVault.withdraw(shares, minAmounts, true);

    // VAULT_OWNER received native ETH for the WETH portion
    assertEq(VAULT_OWNER.balance - ethBefore, received[1]);
    assertGt(received[1], 0);
    // No WETH tokens transferred
    assertEq(mockWeth.balanceOf(VAULT_OWNER), 0);
    // tokenA transferred as ERC20
    assertEq(tokenA.balanceOf(VAULT_OWNER), received[0]);
  }

  /// @notice Withdraw with unwrap=false: WETH stays as an ERC20 token, no native ETH sent
  function test_withdraw_unwrap_false_keeps_weth_token() public {
    SharedVault wethVault = _setupWethVault();
    uint256 shares = wethVault.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];

    vm.prank(VAULT_OWNER);
    uint256[4] memory received = wethVault.withdraw(shares, minAmounts, false);

    // VAULT_OWNER received WETH tokens (not native ETH)
    assertEq(mockWeth.balanceOf(VAULT_OWNER), received[1]);
    assertGt(received[1], 0);
    // No native ETH received
    assertEq(VAULT_OWNER.balance, 0);
    // tokenA received as ERC20
    assertEq(tokenA.balanceOf(VAULT_OWNER), received[0]);
  }

  /// @notice With the dust-proof rounding-up rule, a sub-1-wei proportional WETH slice is
  ///         raised to 1 wei and fully consumed — not refunded, not locked in the vault.
  ///         The precision floor is disabled (set to 0) so only the ceiling rounding is exercised,
  ///         since the depositor intentionally provides amounts (1 wei) that are below the default
  ///         5-decimal floor (1e13 for 18-decimal tokens).
  /// @dev Constructs: tokenA=1e18, mockWeth=1 wei → totalSupply=INITIAL_SHARES
  ///      Deposit amounts=[1 wei tokenA, 1 wei ETH]: sharesOut=min-ratio=10, transferAmounts[weth]
  ///      computed as mulDivRoundingUp(10, 1, INITIAL_SHARES) = 1 wei (ceiling of ~0).
  ///      The 1 wei ETH is wrapped and used — excess refund is 0.
  function test_deposit_eth_dust_amount_is_consumed_via_roundup() public {
    // Disable the precision floor so sub-1e13 amounts are accepted; this test exercises
    // the ceiling-rounding mechanism independently of the floor.
    configManager.setMinTokenPrecision(0);

    SharedVault wv = new SharedVault();
    tokenA.mint(address(this), 1e18);
    vm.deal(address(this), 100 ether);
    mockWeth.deposit{ value: 1 }();

    tokenA.transfer(address(wv), 1e18);
    mockWeth.transfer(address(wv), 1);

    address[4] memory wvTokens = [address(tokenA), address(mockWeth), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1e18), uint256(1), uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    wv.initialize(
      "Dust Vault",
      wvTokens,
      initAmounts,
      VAULT_OWNER,
      VAULT_OWNER,
      address(configManager),
      address(mockWeth)
    );
    vm.stopPrank();

    address depositor = makeAddr("dustDepositor");
    vm.deal(depositor, 1 wei);
    tokenA.mint(depositor, 1);

    vm.startPrank(depositor);
    tokenA.approve(address(wv), 1);

    uint256[4] memory amounts = [uint256(1), uint256(1), uint256(0), uint256(0)];
    uint256 sharesBefore = wv.balanceOf(depositor);

    uint256 vaultWethBefore = mockWeth.balanceOf(address(wv));
    wv.deposit{ value: 1 }(amounts, 0);
    vm.stopPrank();

    assertGt(wv.balanceOf(depositor), sharesBefore, "should receive shares");
    // 1 wei ETH fully consumed (ceiling-rounded transferAmounts[weth]=1 ⇒ excess=0)
    assertEq(depositor.balance, 0, "dust ETH must be consumed, not refunded -- slice rounded up to 1 wei");
    // Vault WETH gained exactly 1 wei from the wrapped ETH
    assertEq(mockWeth.balanceOf(address(wv)), vaultWethBefore + 1, "vault WETH grew by 1 wei");
  }

  // ==================== Double-Dilution Regression Tests ====================

  /// @dev Helper: creates a fresh vault with LP strategy, two equal depositors, and an LP position.
  ///      Each user deposits `depositPerUser` of each token.
  ///      Then `lpAmount` of each token is moved into a mock LP position.
  ///      Final state: idle = 2*depositPerUser - lpAmount, LP = lpAmount, total = 2*depositPerUser per token.
  ///      Alice and Bob each hold 50% of shares → each entitled to `depositPerUser` per token.
  function _setupLPVault(
    uint256 depositPerUser,
    uint256 lpAmount
  ) internal returns (SharedVault v, MockERC20 tA, MockERC20 tB, MockLPPool lpPoolContract) {
    lpPoolContract = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(lpPoolContract));

    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(lpStrategy);
    address[] memory callers = new address[](0);
    address[] memory nfpmsLp = new address[](1);
    nfpmsLp[0] = makeAddr("nfpm");
    cm.initialize(address(this), targets, callers, address(this), 0, nfpmsLp, new address[](0));

    v = new SharedVault();
    tA = new MockERC20("Token A", "A");
    tB = new MockERC20("Token B", "B");

    // Alice (VAULT_OWNER) seeds vault
    tA.mint(address(this), depositPerUser);
    tB.mint(address(this), depositPerUser);
    tA.transfer(address(v), depositPerUser);
    tB.transfer(address(v), depositPerUser);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [depositPerUser, depositPerUser, uint256(0), uint256(0)];
    vm.startPrank(VAULT_OWNER);
    v.initialize("TestVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0));
    vm.stopPrank();

    // Bob deposits the same amounts → gets equal shares
    address bob = makeAddr("bob");
    tA.mint(bob, depositPerUser);
    tB.mint(bob, depositPerUser);
    vm.startPrank(bob);
    tA.approve(address(v), type(uint256).max);
    tB.approve(address(v), type(uint256).max);
    uint256[4] memory bobDeposit = [depositPerUser, depositPerUser, uint256(0), uint256(0)];
    v.deposit(bobDeposit, 0);
    vm.stopPrank();

    // Move lpAmount of each into LP via strategy execute
    if (lpAmount > 0) {
      vm.startPrank(VAULT_OWNER);
      address fakeNfpm = makeAddr("nfpm");
      bytes memory stratData = abi.encode(fakeNfpm, uint256(1), address(tA), address(tB), lpAmount, lpAmount);
      ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
      actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
      v.execute(actions);
      vm.stopPrank();
    }
  }

  /// @notice Regression: withdraw with active LP must not double-dilute the LP exit return.
  /// Each user deposits 100e18 per token, vault creates 100e18 LP.
  /// Final state: idle=100e18, LP=100e18, total=200e18 per token, 50/50 shares.
  /// Alice's 50% = 100e18 per token.
  /// Before fix: exitProportional returns 50e18 → idle=150e18 → amounts=50/100*150=75e18 (WRONG).
  /// After fix:  amounts = 50/100*100(original idle) + 50(LP return) = 100e18 (CORRECT).
  function test_withdraw_no_double_dilution_with_lp() public {
    // depositPerUser=100e18, lpAmount=100e18
    // total=200e18, idle=100e18, LP=100e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB, ) = _setupLPVault(100e18, 100e18);

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    assertEq(aliceShares, v.INITIAL_SHARES());
    assertEq(v.totalSupply(), v.INITIAL_SHARES() * 2);

    // Verify total balances
    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 200e18, "total A = 200e18");
    assertEq(totalBal[1], 200e18, "total B = 200e18");

    // Preview: Alice's 50% of 200e18 = 100e18
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 100e18, "preview A = 50% of 200e18");
    assertEq(preview[1], 100e18, "preview B = 50% of 200e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    // Core assertion: Alice gets her full proportional share
    assertEq(received[0], 100e18, "Alice must receive 100e18 A (not 75e18)");
    assertEq(received[1], 100e18, "Alice must receive 100e18 B (not 75e18)");
    assertEq(received[0], preview[0], "actual must match preview for A");
    assertEq(received[1], preview[1], "actual must match preview for B");

    // Bob withdraws the remainder — vault must be perfectly drained
    address bob = makeAddr("bob");
    uint256[4] memory bobPreview = v.previewWithdraw(v.balanceOf(bob));
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 100e18, "Bob must receive 100e18 A");
    assertEq(bobReceived[1], 100e18, "Bob must receive 100e18 B");
    assertEq(bobReceived[0], bobPreview[0], "Bob actual must match preview for A");
    assertEq(bobReceived[1], bobPreview[1], "Bob actual must match preview for B");

    assertEq(v.totalSupply(), 0, "all shares burned");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  /// @notice Heavy LP allocation — matches the bug report's Alice/Bob scenario.
  /// Each user deposits 500e18, vault creates 900e18 LP.
  /// Final: idle=100e18, LP=900e18, total=1000e18 per token.
  /// Alice's 50% = 500e18.
  /// Before fix: exit returns 450 → idle=550 → amounts=50%*550=275 (WRONG).
  /// After fix:  amounts = 50%*100 + 450 = 500 (CORRECT).
  function test_withdraw_heavy_lp_no_double_dilution() public {
    // depositPerUser=500e18, lpAmount=900e18
    // total=1000e18, idle=100e18, LP=900e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB, ) = _setupLPVault(500e18, 900e18);

    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 1000e18, "total A");
    assertEq(totalBal[1], 1000e18, "total B");
    assertEq(tA.balanceOf(address(v)), 100e18, "idle A = 100e18");

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 500e18, "preview A = 50% of 1000e18");
    assertEq(preview[1], 500e18, "preview B = 50% of 1000e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    assertEq(received[0], 500e18, "Alice A = 500e18 (not 275e18)");
    assertEq(received[1], 500e18, "Alice B = 500e18 (not 275e18)");
    assertEq(received[0], preview[0], "match preview A");
    assertEq(received[1], preview[1], "match preview B");

    // Bob gets the other half — vault drains cleanly
    address bob = makeAddr("bob");
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 500e18, "Bob A");
    assertEq(bobReceived[1], 500e18, "Bob B");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  /// @notice Edge case: vault has zero idle, 100% LP.
  /// depositPerUser=50e18, lpAmount=100e18 → idle=0, LP=100e18, total=100e18.
  /// Alice's 50% = 50e18.
  function test_withdraw_zero_idle_all_lp_no_double_dilution() public {
    // depositPerUser=50e18, lpAmount=100e18
    // total=100e18, idle=0, LP=100e18 per token
    (SharedVault v, MockERC20 tA, MockERC20 tB, ) = _setupLPVault(50e18, 100e18);

    assertEq(tA.balanceOf(address(v)), 0, "idle A = 0");
    uint256[4] memory totalBal = v.getTotalBalances();
    assertEq(totalBal[0], 100e18, "total A = 100e18");

    uint256 aliceShares = v.balanceOf(VAULT_OWNER);
    uint256[4] memory preview = v.previewWithdraw(aliceShares);
    assertEq(preview[0], 50e18, "preview A = 50% of 100e18");

    vm.startPrank(VAULT_OWNER);
    uint256[4] memory minAmounts;
    uint256[4] memory received = v.withdraw(aliceShares, minAmounts, false);
    vm.stopPrank();

    assertEq(received[0], 50e18, "Alice A");
    assertEq(received[1], 50e18, "Alice B");
    assertEq(received[0], preview[0], "match preview A");

    // Bob gets remainder
    address bob = makeAddr("bob");
    vm.startPrank(bob);
    uint256[4] memory bobReceived = v.withdraw(v.balanceOf(bob), minAmounts, false);
    vm.stopPrank();

    assertEq(bobReceived[0], 50e18, "Bob A");
    assertEq(tA.balanceOf(address(v)), 0, "vault A drained");
    assertEq(tB.balanceOf(address(v)), 0, "vault B drained");
  }

  // ==================== execute() — DELEGATECALL + token changes ====================

  /// @notice DELEGATECALL returning an empty PositionChange[] is the token-change case:
  ///         the strategy runs in vault context (e.g., harvest+swap) and only vault token
  ///         balances change. The vault sees the idle balance difference with no position tracking.
  function test_execute_delegatecall_token_changes_empty_position_array() public {
    // Simulate a harvest: externally mint tokenA into vault before the strategy "runs"
    // (in a real harvest the strategy would collect fees and they'd land in the vault)
    uint256 harvestAmount = 5e18;
    tokenA.mint(address(vault), harvestAmount);
    uint256 balanceBefore = tokenA.balanceOf(address(vault));

    vm.startPrank(VAULT_OWNER);
    // MockSharedStrategy.execute() returns empty PositionChange[] — simulates a token-only op
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(mockStrategy),
      abi.encode(uint256(0)),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);
    vm.stopPrank();

    // No position changes expected
    assertEq(vault.getPositionCount(), 0, "no positions should be tracked");
    // Token balance reflects the externally-added harvest (vault always sees current idle balance)
    assertEq(tokenA.balanceOf(address(vault)), balanceBefore, "token balance unchanged by empty strategy");
  }

  /// @notice DELEGATECALL with non-empty PositionChange[] → LP position tracked.
  ///         This is the existing behavior confirmed as the "position change" case.
  function test_execute_delegatecall_position_changes_tracked() public {
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));

    vm.startPrank(address(this));
    address[] memory extraTargets1 = new address[](1);
    extraTargets1[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets1, true);
    vm.stopPrank();

    address mockNfpm = address(0xDEAD);
    uint256 tokenId = 1;

    // Give vault some tokens so the LP deposit can pull them
    tokenA.mint(address(vault), 10e18);
    tokenB.mint(address(pool), 10e18); // pool needs tokenB to return on exit

    vm.startPrank(VAULT_OWNER);
    bytes memory stratData = abi.encode(
      mockNfpm,
      tokenId,
      address(tokenA),
      address(tokenB),
      uint256(10e18),
      uint256(0)
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(lpStrategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "one LP position should be tracked");
    (address strategy, address nfpm, uint256 tid, , ) = vault.getPosition(0);
    assertEq(strategy, address(lpStrategy), "strategy stored correctly");
    assertEq(nfpm, mockNfpm, "nfpm stored correctly");
    assertEq(tid, tokenId, "tokenId stored correctly");
  }

  // ==================== execute() — CALL_WITH_POSITIONS ====================

  /// @notice CALL_WITH_POSITIONS: direct call returns PositionChange[] → LP position added.
  function test_execute_call_with_positions_adds_position() public {
    address mockNfpm = address(0xBEEF);
    uint256 tokenId = 42;

    bytes memory callData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (mockNfpm, tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "position should be added");
    (address strategy, address nfpm, uint256 tid, address t0, address t1) = vault.getPosition(0);
    assertEq(strategy, address(directCreator), "strategy is the direct creator target");
    assertEq(nfpm, mockNfpm);
    assertEq(tid, tokenId);
    assertEq(t0, address(tokenA));
    assertEq(t1, address(tokenB));
  }

  /// @notice CALL_WITH_POSITIONS: direct call returns PositionChange[] with isAdd=false → position removed.
  function test_execute_call_with_positions_removes_position() public {
    // First add a position via DELEGATECALL
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory extraTargets2 = new address[](1);
    extraTargets2[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets2, true);

    address mockNfpm = address(0xBEEF);
    uint256 tokenId = 99;

    tokenA.mint(address(vault), 10e18);
    tokenB.mint(address(pool), 10e18);

    vm.startPrank(VAULT_OWNER);
    bytes memory addData = abi.encode(mockNfpm, tokenId, address(tokenA), address(tokenB), uint256(10e18), uint256(0));
    ISharedVault.Action[] memory addActions = new ISharedVault.Action[](1);
    addActions[0] = ISharedVault.Action(address(lpStrategy), addData, ISharedCommon.CallType.DELEGATECALL);
    vault.execute(addActions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 1, "position added");

    // Now remove via CALL_WITH_POSITIONS
    bytes memory removeCallData = abi.encodeCall(
      MockDirectPositionCreator.removePosition,
      (mockNfpm, tokenId, address(tokenA), address(tokenB))
    );

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory removeActions = new ISharedVault.Action[](1);
    removeActions[0] = ISharedVault.Action(
      address(directCreator),
      removeCallData,
      ISharedCommon.CallType.CALL_WITH_POSITIONS
    );
    vault.execute(removeActions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "position should be removed");
  }

  /// @notice CALL_WITH_POSITIONS with empty PositionChange[] result → no tracking change.
  function test_execute_call_with_positions_empty_result_no_change() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.noChanges, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vault.execute(actions);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "no positions should be added");
  }

  /// @notice CALL_WITH_POSITIONS: target call reverts → execute reverts with the error message.
  function test_execute_call_with_positions_reverts_on_failure() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.alwaysFail, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert("DirectCreator: always fails");
    vault.execute(actions);
    vm.stopPrank();
  }

  /// @notice CALL_WITH_POSITIONS: non-whitelisted target → reverts with InvalidTarget.
  function test_execute_call_with_positions_non_whitelisted_target() public {
    bytes memory callData = abi.encodeCall(MockDirectPositionCreator.noChanges, ());

    vm.startPrank(VAULT_OWNER);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    // Use failingStrategy address which is NOT whitelisted
    actions[0] = ISharedVault.Action(address(failingStrategy), callData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidTarget.selector, address(failingStrategy)));
    vault.execute(actions);
    vm.stopPrank();
  }

  /// @notice Mixed batch: DELEGATECALL (position) + CALL (swap) + CALL_WITH_POSITIONS (position) in one execute().
  function test_execute_mixed_batch_all_three_call_types() public {
    // Setup: whitelist lpStrategy
    MockLPPool pool = new MockLPPool();
    MockLPExitStrategy lpStrategy = new MockLPExitStrategy(address(pool));
    address[] memory extraTargets3 = new address[](1);
    extraTargets3[0] = address(lpStrategy);
    configManager.setWhitelistTargets(extraTargets3, true);

    // Prepare tokens
    tokenA.mint(address(vault), 20e18);
    tokenB.mint(address(pool), 10e18);
    tokenB.mint(address(swapTarget), 5e18);

    address delegatecallNfpm = address(0xAAAA);
    address callWithPositionsNfpm = address(0xBBBB);

    // Action 1: DELEGATECALL — strategy creates LP position
    bytes memory dcData = abi.encode(
      delegatecallNfpm,
      uint256(1),
      address(tokenA),
      address(tokenB),
      uint256(10e18),
      uint256(0)
    );

    // Action 2: CALL — token swap tokenA → tokenB
    bytes memory swapCalldata = abi.encodeCall(MockSwapTarget.swap, (address(tokenA), address(tokenB), 5e18));
    bytes memory swapData = abi.encode(address(tokenA), address(tokenB), 5e18, uint256(0), swapCalldata);

    // Action 3: CALL_WITH_POSITIONS — direct call creates another position
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (callWithPositionsNfpm, 2, address(tokenA), address(tokenB))
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](3);
    actions[0] = ISharedVault.Action(address(lpStrategy), dcData, ISharedCommon.CallType.DELEGATECALL);
    actions[1] = ISharedVault.Action(address(swapTarget), swapData, ISharedCommon.CallType.CALL);
    actions[2] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.startPrank(VAULT_OWNER);
    vault.execute(actions);
    vm.stopPrank();

    // Two LP positions tracked (one from DELEGATECALL, one from CALL_WITH_POSITIONS)
    assertEq(vault.getPositionCount(), 2, "two positions should be tracked");
    // Swap was also successful
    assertGt(tokenB.balanceOf(address(vault)), 0, "tokenB balance increased from swap");
  }

  // ==================== Position Limit Tests ====================

  // Helper: add a unique position via CALL_WITH_POSITIONS using directCreator.
  // tokenId is used to make each (nfpm, tokenId) pair unique.
  function _addPositionViaDirectCreator(uint256 tokenId) internal {
    address nfpm = makeAddr("nfpm");
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (nfpm, tokenId, address(tokenA), address(tokenB))
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
  }

  function test_maxPositions_defaultIs20() public view {
    assertEq(configManager.maxPositions(), 20);
  }

  function test_maxPositions_revertsWhenLimitReached() public {
    // Set limit to 2, add 2 positions, then verify the 3rd reverts
    configManager.setMaxPositions(2);

    _addPositionViaDirectCreator(1);
    _addPositionViaDirectCreator(2);
    assertEq(vault.getPositionCount(), 2);

    address nfpm = makeAddr("nfpm");
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (nfpm, 3, address(tokenA), address(tokenB))
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.prank(VAULT_OWNER);
    vm.expectRevert(ISharedCommon.TooManyPositions.selector);
    vault.execute(actions);
  }

  function test_maxPositions_allowsExactlyLimitPositions() public {
    configManager.setMaxPositions(3);

    _addPositionViaDirectCreator(1);
    _addPositionViaDirectCreator(2);
    _addPositionViaDirectCreator(3);

    assertEq(vault.getPositionCount(), 3);
  }

  function test_maxPositions_raisingLimitAllowsMorePositions() public {
    configManager.setMaxPositions(1);
    _addPositionViaDirectCreator(1);
    assertEq(vault.getPositionCount(), 1);

    // Raise the limit
    configManager.setMaxPositions(2);
    _addPositionViaDirectCreator(2);
    assertEq(vault.getPositionCount(), 2);
  }

  function test_maxPositions_loweringLimitDoesNotBlockWithdraw() public {
    // Add 3 positions, then lower limit to 1 — withdrawal must still work
    configManager.setMaxPositions(3);
    _addPositionViaDirectCreator(1);
    _addPositionViaDirectCreator(2);
    _addPositionViaDirectCreator(3);
    assertEq(vault.getPositionCount(), 3);

    configManager.setMaxPositions(1);

    // Full withdrawal succeeds even though position count (3) exceeds new limit (1)
    uint256 shares = vault.balanceOf(VAULT_OWNER);
    uint256[4] memory minOut;
    vm.prank(VAULT_OWNER);
    vault.withdraw(shares, minOut, false);

    // exitProportional on MockDirectPositionCreator returns empty changes, so positions stay
    // tracked (no removal) — the point is withdraw doesn't revert
    assertEq(vault.totalSupply(), 0);
  }

  // ==================== Dust-Floor Tests (minTokenPrecision) ====================
  //
  // The dust floor is expressed as a decimal-place precision level rather than a raw amount.
  // For a token with `d` decimals and configured precision `prec`, the effective min is:
  //
  //     minAmt = 10 ** max(0, d - prec)
  //
  // Default precision = 5, meaning 0.00001 of any token:
  //   18-decimal token (e.g. WETH):  10**(18-5) = 1e13 wei
  //    6-decimal token (e.g. USDC):  10**(6-5)  = 10
  //    8-decimal token (e.g. WBTC):  10**(8-5)  = 1000 sats
  //
  // Both mock tokens in this test suite have 18 decimals, so precision 5 -> floor = 1e13.
  //
  // Asymmetric behaviour:
  //   DEPOSIT  -- slices rounded UP (ceiling) then raised to minAmt. Forces depositor to
  //      over-pay dust slices, blocking the share-dilution attack.
  //   WITHDRAW -- plain floor division (mulDiv). Dust is forwarded as-is to the caller.
  //      If the call originated from SharedVaultGateway, the gateway returns un-swappable
  //      dust directly to the user rather than failing the transaction.

  // ---- config: setMinTokenPrecision ----

  function test_setMinTokenPrecision_default_is_five() public view {
    assertEq(configManager.minTokenPrecision(), 5, "default precision = 5");
  }

  function test_setMinTokenPrecision_owner_stores_value_and_emits() public {
    vm.expectEmit(true, true, true, true);
    emit ISharedConfigManager.MinTokenPrecisionUpdated(3);
    configManager.setMinTokenPrecision(3);

    assertEq(configManager.minTokenPrecision(), 3, "precision stored");
  }

  function test_setMinTokenPrecision_reverts_for_non_owner() public {
    vm.prank(NON_AUTHORIZED);
    vm.expectRevert();
    configManager.setMinTokenPrecision(3);
  }

  function test_setMinTokenPrecision_zero_disables_floor() public {
    configManager.setMinTokenPrecision(0);
    assertEq(configManager.minTokenPrecision(), 0, "floor disabled");
  }

  // ---- deposit: rounding up + precision-derived floor ----

  /// @dev Vault with tokenB at 50 wei dust (18-decimal mock tokens).
  ///      totalBalances = [100e18, 50], totalSupply = INITIAL_SHARES (10e18).
  function _setupDustVault() internal returns (SharedVault v) {
    v = new SharedVault();
    tokenA.mint(address(this), 100e18);
    tokenB.mint(address(this), 50);
    tokenA.transfer(address(v), 100e18);
    tokenB.transfer(address(v), 50);

    address[4] memory vtokens = [address(tokenA), address(tokenB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(100e18), uint256(50), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    v.initialize("DustVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(configManager), address(0));
  }

  /// @notice The dilution attack is blocked by ceiling rounding alone (no floor needed).
  ///         A depositor who provides 0 of the dust token but non-zero of the majority token
  ///         cannot receive shares -- the ceiling raises the required dust slice to >= 1 wei.
  function test_deposit_blocks_dust_dilution_attack_via_ceiling() public {
    SharedVault v = _setupDustVault();

    tokenA.mint(DEPOSITOR, 1e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256[4] memory attackAmounts = [uint256(1e18), uint256(0), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit(attackAmounts, 0);
    vm.stopPrank();
  }

  /// @notice With precision = 5 and 18-decimal tokens, the per-token floor is 10**(18-5) = 1e13.
  ///         A depositor providing tokenB below 1e13 must be rejected even if ceiling-rounded
  ///         proportional is already < 1e13.
  ///
  ///         Vault state: tokenB total = 50 wei, totalSupply = 10e18.
  ///         Depositor supplies 1e18 A + 5 wei B.
  ///         sharesOut from A = floor(1e18 * 10e18 / 100e18) = 1e17.
  ///         Ceiling proportional B = ceil(1e17 * 50 / 10e18) = 1.
  ///         Floor (precision=5, dec=18) = 1e13.
  ///         transferAmounts[B] = max(1, 1e13) = 1e13. Depositor provides 5 < 1e13 => reverts.
  function test_deposit_requires_at_least_precision_floor_for_dust_slice() public {
    SharedVault v = _setupDustVault();
    // Default precision = 5. floor = 10**(18-5) = 1e13.

    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 5);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256[4] memory tooLittle = [uint256(1e18), uint256(5), uint256(0), uint256(0)];
    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit(tooLittle, 0);
    vm.stopPrank();
  }

  /// @notice Happy path: depositor supplies enough to clear the precision floor.
  ///         Vault pulls exactly the computed floor (1e13) from the depositor's tokenB.
  function test_deposit_pulls_exactly_precision_floor_for_dust_slice() public {
    SharedVault v = _setupDustVault();
    // precision = 5, dec = 18 => floor = 1e13.

    uint256 expectedFloor = 1e13;
    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 2e13); // more than the floor
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256 bBalBefore = tokenB.balanceOf(DEPOSITOR);
    uint256[4] memory amts = [uint256(1e18), uint256(2e13), uint256(0), uint256(0)];
    uint256 shares = v.deposit(amts, 0);
    vm.stopPrank();

    assertGt(shares, 0, "shares minted");
    assertEq(tokenB.balanceOf(DEPOSITOR), bBalBefore - expectedFloor, "depositor pays exactly the precision floor");
    assertEq(tokenB.balanceOf(address(v)), 50 + expectedFloor, "vault tokenB grew by exactly the floor");
  }

  /// @notice Precision = 0 disables the floor. Ceiling rounding is still active.
  ///         A dust slice of 1 wei passes because precision=0 => _minTokenAmt returns 0.
  function test_deposit_precision_zero_disables_floor_ceiling_still_active() public {
    SharedVault v = _setupDustVault();
    configManager.setMinTokenPrecision(0);

    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 1);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    uint256[4] memory amts = [uint256(1e18), uint256(1), uint256(0), uint256(0)];
    uint256 shares = v.deposit(amts, 0);
    vm.stopPrank();

    assertGt(shares, 0, "shares minted when providing exactly 1 wei dust");
    assertEq(tokenB.balanceOf(address(v)), 51, "vault pulled exactly 1 wei (ceiling rounding)");
  }

  /// @notice Normal-sized deposits are unaffected by the floor.
  ///         A 10% proportional deposit far exceeds the precision floor on all tokens.
  function test_deposit_above_floor_behaves_normally() public {
    // Existing vault: 100e18 A + 200e18 B, precision=5 -> floor=1e13 per token.
    // 10% deposit yields 10e18 A and 20e18 B -- both >> 1e13.
    tokenA.mint(DEPOSITOR, 10e18);
    tokenB.mint(DEPOSITOR, 20e18);
    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(vault), type(uint256).max);
    tokenB.approve(address(vault), type(uint256).max);

    uint256[4] memory amts = [uint256(10e18), uint256(20e18), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(amts, 0);
    vm.stopPrank();

    assertEq(shares, vault.INITIAL_SHARES() / 10, "10% of INITIAL_SHARES");
    assertEq(tokenA.balanceOf(address(vault)), 110e18);
    assertEq(tokenB.balanceOf(address(vault)), 220e18);
  }

  /// @notice The floor scales correctly with different precision levels.
  ///         Precision = 17 on an 18-decimal token => floor = 10**(18-17) = 10 wei.
  ///         This simulates "0.1 unit" precision on a small-balance token.
  function test_deposit_precision_scales_per_decimal_count() public {
    SharedVault v = _setupDustVault();
    // Precision 17 => floor = 10**(18-17) = 10 wei (both tokens are 18-decimal mocks).
    configManager.setMinTokenPrecision(17);

    tokenA.mint(DEPOSITOR, 1e18);
    tokenB.mint(DEPOSITOR, 5); // 5 wei < 10-wei floor

    vm.startPrank(DEPOSITOR);
    tokenA.approve(address(v), type(uint256).max);
    tokenB.approve(address(v), type(uint256).max);

    vm.expectRevert(ISharedCommon.InvalidRatio.selector);
    v.deposit([uint256(1e18), uint256(5), uint256(0), uint256(0)], 0);

    tokenB.mint(DEPOSITOR, 10); // now has 15 wei -- enough to clear 10-wei floor
    v.deposit([uint256(1e18), uint256(15), uint256(0), uint256(0)], 0);
    vm.stopPrank();

    // Vault pulled exactly 10 wei of tokenB (the floor).
    assertEq(tokenB.balanceOf(address(v)), 60, "vault pulled exactly the 10-wei floor");
  }

  // ---- withdraw: dust forwarded to caller ----

  /// @notice Withdrawal dust (proportional slices below any conceivable swap threshold) is
  ///         forwarded to the caller, not silently discarded.
  ///         Burning 1 wei share from the 10e18:200e18 vault yields 10 wei A and 20 wei B.
  ///         These tiny amounts are transferred even though they are well below 1e13 (precision-5 floor).
  ///         If called via the gateway, the gateway may return them directly to the user.
  function test_withdraw_forwards_dust_to_caller() public {
    uint256 sharesToBurn = 1;
    uint256 aVaultBefore = tokenA.balanceOf(address(vault));
    uint256 bVaultBefore = tokenB.balanceOf(address(vault));
    uint256 aOwnerBefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 bOwnerBefore = tokenB.balanceOf(VAULT_OWNER);

    uint256[4] memory minAmounts;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = vault.withdraw(sharesToBurn, minAmounts, false);

    // 1 / 10e18 of 100e18 A = 10 wei; 1 / 10e18 of 200e18 B = 20 wei.
    assertEq(received[0], 10, "10 wei A forwarded to caller");
    assertEq(received[1], 20, "20 wei B forwarded to caller");
    assertEq(tokenA.balanceOf(address(vault)), aVaultBefore - 10, "vault sent 10 wei A");
    assertEq(tokenB.balanceOf(address(vault)), bVaultBefore - 20, "vault sent 20 wei B");
    assertEq(tokenA.balanceOf(VAULT_OWNER), aOwnerBefore + 10, "owner received 10 wei A");
    assertEq(tokenB.balanceOf(VAULT_OWNER), bOwnerBefore + 20, "owner received 20 wei B");
  }

  /// @notice A normal-sized withdrawal transfers the full proportional amount.
  ///         Half of INITIAL_SHARES yields 50e18 A + 100e18 B.
  function test_withdraw_proportional_transfers_normally() public {
    uint256 ownerShares = vault.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;
    uint256[4] memory minAmounts;

    vm.prank(VAULT_OWNER);
    uint256[4] memory received = vault.withdraw(halfShares, minAmounts, false);

    assertEq(received[0], 50e18, "half shares yields 50e18 A");
    assertEq(received[1], 100e18, "half shares yields 100e18 B");
  }

  /// @notice minTokenPrecision has no effect on withdraw -- dust is always forwarded.
  ///         With 1 wei share burn proportional = 10 wei A and 20 wei B, regardless of
  ///         how precision is configured.
  function test_withdraw_precision_setting_does_not_affect_output() public {
    // Even with precision=5 (floor=1e13), dust slices are forwarded unchanged.
    uint256 aOwnerBefore = tokenA.balanceOf(VAULT_OWNER);
    uint256 bOwnerBefore = tokenB.balanceOf(VAULT_OWNER);
    uint256[4] memory minAmounts;
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = vault.withdraw(1, minAmounts, false);

    assertEq(received[0], 10, "10 wei A forwarded (precision setting irrelevant on withdraw)");
    assertEq(received[1], 20, "20 wei B forwarded (precision setting irrelevant on withdraw)");
    assertEq(tokenA.balanceOf(VAULT_OWNER), aOwnerBefore + 10, "owner received 10 wei A");
    assertEq(tokenB.balanceOf(VAULT_OWNER), bOwnerBefore + 20, "owner received 20 wei B");
  }

  /// @notice Per-token proportional withdrawal: each token's slice is forwarded independently.
  ///         Vault: 100e18 A + 50 B, totalSupply = 10e18.
  ///         Half-share burn (5e18 / 10e18):
  ///           proportional A = mulDiv(5e18, 100e18, 10e18) = 50e18
  ///           proportional B = mulDiv(5e18, 50,     10e18) = 25 wei
  ///         Both slices -- large and dust -- are forwarded to the caller regardless of precision.
  function test_withdraw_per_token_all_slices_forwarded_to_caller() public {
    // Build a vault where tokenB is dust (50 wei) but tokenA is large.
    SharedVault v = _setupDustVault(); // 100e18 A, 50 B, totalSupply = 10e18

    uint256 ownerShares = v.balanceOf(VAULT_OWNER);
    uint256 halfShares = ownerShares / 2;
    uint256[4] memory minAmounts;

    uint256 aVaultBefore = tokenA.balanceOf(address(v));
    uint256 bVaultBefore = tokenB.balanceOf(address(v));
    vm.prank(VAULT_OWNER);
    uint256[4] memory received = v.withdraw(halfShares, minAmounts, false);

    assertEq(received[0], 50e18, "tokenA slice (50e18) forwarded");
    assertEq(received[1], 25, "tokenB dust slice (25 wei) forwarded to caller");
    assertEq(tokenA.balanceOf(address(v)), aVaultBefore - 50e18, "tokenA left vault");
    assertEq(tokenB.balanceOf(address(v)), bVaultBefore - 25, "tokenB dust left vault");
  }

  function test_maxPositions_duplicatePositionDoesNotConsumeSlot() public {
    // Adding the same (nfpm, tokenId) twice must not count as two positions
    configManager.setMaxPositions(1);

    address nfpm = makeAddr("nfpm");
    bytes memory cwpData = abi.encodeCall(
      MockDirectPositionCreator.createPosition,
      (nfpm, 99, address(tokenA), address(tokenB))
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(directCreator), cwpData, ISharedCommon.CallType.CALL_WITH_POSITIONS);

    vm.prank(VAULT_OWNER);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1);

    // Same (nfpm, tokenId) again — _addPosition returns early, no TooManyPositions
    vm.prank(VAULT_OWNER);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1);
  }

  // ==================== Rewards-Ratio Fix: Principal-Only Scaling Tests ====================
  //
  // Regression suite for the bug where `_depositProportionalToAllPositions` scaled per-position
  // top-ups by `getPositionAmounts` (principal + uncollected fees). When a position's principal
  // ratio (set by the current tick range) diverges from its uncollected-fees ratio (set by
  // historical swap flow), this would produce off-range `(amount0, amount1)` desireds that the
  // underlying AMM's `increaseLiquidity` cannot consume in proportion — leading to either
  // silent idle leakage (slippageBps == 0) or a revert via `amount*Min` (slippageBps > 0).
  //
  // Scenario throughout this section (chosen so the two ratios diverge cleanly):
  //   - position principal:        30 A : 70 B   (3:7 range ratio)
  //   - position uncollected fees: 10 A : 10 B   (1:1 rewards ratio — different from range)
  //   - getPositionAmounts:        40 A : 80 B   (sum; 1:2 total ratio)
  //   - getPositionPrincipalAmounts: 30 A : 70 B (fix uses this for the LP top-up)
  //
  // The fix guarantees top-ups go in at the 3:7 principal ratio, regardless of how fees have
  // accrued — and the depositor's proportional share of the fees simply stays idle in the vault.

  /// @dev Builds a fresh vault with one `MockRewardsAwareStrategy` position whose principal
  ///      and rewards ratios diverge. Returns the vault, tokens, recorder, and the (nfpm,
  ///      tokenId) of the position. Post-setup state:
  ///        - vault idle: 20 A, 80 B (initial 50/150 minus 30/70 moved into the position)
  ///        - position: 30 A / 70 B principal  +  10 A / 10 B virtual rewards
  ///        - totalSupply = INITIAL_SHARES (owner holds all shares)
  function _setupVaultWithRewardsAwarePosition()
    internal
    returns (
      SharedVault rewardsVault,
      MockERC20 tA,
      MockERC20 tB,
      DepositProportionalRecorder recorder,
      MockERC721 nfpm,
      uint256 tokenId,
      MockRewardsAwareStrategy strat
    )
  {
    // --- Arrange: deploy isolated token/pool/recorder/strategy for this scenario -------------
    tA = new MockERC20("RewardsA", "RA");
    tB = new MockERC20("RewardsB", "RB");
    MockLPPool pool = new MockLPPool();
    recorder = new DepositProportionalRecorder();
    strat = new MockRewardsAwareStrategy(
      address(pool),
      address(recorder),
      30e18, // principal0
      70e18, // principal1
      10e18, // rewards0 (uncollected fees, virtual)
      10e18 // rewards1
    );
    nfpm = new MockERC721();
    tokenId = 1;

    // --- Arrange: whitelist strategy + nfpm in an isolated config manager --------------------
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strat);
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(nfpm);
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    // --- Arrange: seed the vault with idle balances large enough to cover principal transfer
    rewardsVault = new SharedVault();
    tA.mint(address(this), 50e18);
    tB.mint(address(this), 150e18);
    tA.transfer(address(rewardsVault), 50e18);
    tB.transfer(address(rewardsVault), 150e18);

    address[4] memory vtokens = [address(tA), address(tB), address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(50e18), uint256(150e18), uint256(0), uint256(0)];
    vm.prank(VAULT_OWNER);
    rewardsVault.initialize("RewardsVault", vtokens, initAmounts, VAULT_OWNER, VAULT_OWNER, address(cm), address(0));

    // --- Act: register the position by delegatecall-executing the strategy -------------------
    nfpm.mint(address(rewardsVault), tokenId);
    bytes memory stratData = abi.encode(address(nfpm), tokenId, address(tA), address(tB));
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strat), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(VAULT_OWNER);
    rewardsVault.execute(actions);

    // --- Assert: setup preconditions (sanity guard for the rest of the suite) ----------------
    assertEq(tA.balanceOf(address(rewardsVault)), 20e18, "setup: vault idle A = initial - principal0");
    assertEq(tB.balanceOf(address(rewardsVault)), 80e18, "setup: vault idle B = initial - principal1");
    assertEq(rewardsVault.getPositionCount(), 1, "setup: one position tracked");

    (uint256 totalA, uint256 totalB) = strat.getPositionAmounts(address(nfpm), tokenId);
    assertEq(totalA, 40e18, "setup: getPositionAmounts includes fees (30 + 10)");
    assertEq(totalB, 80e18, "setup: getPositionAmounts includes fees (70 + 10)");

    (uint256 princA, uint256 princB) = strat.getPositionPrincipalAmounts(address(nfpm), tokenId);
    assertEq(princA, 30e18, "setup: getPositionPrincipalAmounts excludes fees");
    assertEq(princB, 70e18, "setup: getPositionPrincipalAmounts excludes fees");
  }

  /// @notice The vault's LP top-up is scaled by *principal* amounts, not by total (principal + rewards).
  ///         With 40:80 totals but 30:70 principal, a 30:80 proportional deposit must be split
  ///         into a 15:35 LP top-up (3:7 range ratio) — NOT 20:40 (1:2 totals ratio), which is the
  ///         pre-fix behavior and would push tokens in at the wrong range ratio.
  function test_deposit_rewardsRatio_usesPrincipalAmountsForLPTopup() public {
    // Arrange: fresh vault with a rewards-bearing position. State documented in helper.
    (
      SharedVault rv,
      MockERC20 tA,
      MockERC20 tB,
      DepositProportionalRecorder recorder,
      ,
      ,

    ) = _setupVaultWithRewardsAwarePosition();

    // totalBalances = (20 idle + 40 position, 80 idle + 80 position) = (60, 160).
    // A 50% proportional deposit therefore transfers (30, 80).
    tA.mint(DEPOSITOR, 30e18);
    tB.mint(DEPOSITOR, 80e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);

    // Act: proportional deposit with zero slippage guard (so the recorder captures intent
    //      regardless of how the mock pool ends up absorbing the tokens).
    uint256[4] memory amounts = [uint256(30e18), uint256(80e18), uint256(0), uint256(0)];
    rv.deposit(amounts, 0);
    vm.stopPrank();

    // Assert: exactly one LP top-up happened, and at the principal (3:7) ratio, not the total (1:2) ratio.
    assertEq(recorder.callCount(), 1, "depositProportional called exactly once");
    // FIX: toAdd0 = transferAmount0 * principal0 / total0 = 30 * 30 / 60 = 15
    assertEq(recorder.lastAmount0(), 15e18, "LP top-up token0 scaled by principal, not totals");
    // FIX: toAdd1 = transferAmount1 * principal1 / total1 = 80 * 70 / 160 = 35
    assertEq(recorder.lastAmount1(), 35e18, "LP top-up token1 scaled by principal, not totals");

    // Cross-check the ratio explicitly — the bug manifests as a non-3:7 ratio here.
    assertEq(
      recorder.lastAmount0() * 7,
      recorder.lastAmount1() * 3,
      "LP top-up ratio must equal principal ratio (3:7), regardless of uncollected fees"
    );
  }

  /// @notice With the fix, a deposit carrying a reasonable slippage guard (1%) no longer reverts
  ///         just because the position's rewards ratio diverges from its principal ratio. Before
  ///         the fix this would revert with `"OffRatioDeposit"` because the pre-fix top-up at the
  ///         totals-ratio consumes less than `amountMin` on the binding side.
  function test_deposit_rewardsRatio_doesNotRevertUnderSlippageCheck() public {
    (SharedVault rv, MockERC20 tA, MockERC20 tB, , , , ) = _setupVaultWithRewardsAwarePosition();

    tA.mint(DEPOSITOR, 30e18);
    tB.mint(DEPOSITOR, 80e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);

    uint256[4] memory amounts = [uint256(30e18), uint256(80e18), uint256(0), uint256(0)];
    // 1% slippage on the LP top-up. The mock's depositProportional mirrors real V3 semantics
    // and reverts `"OffRatioDeposit"` if the binding-side consumption falls below amountMin.
    uint256 sharesMinted = rv.deposit(amounts, uint16(100));
    vm.stopPrank();

    // Assert: deposit succeeded and minted non-zero shares proportional to the 50% contribution.
    assertGt(sharesMinted, 0, "deposit minted shares");
    assertEq(rv.balanceOf(DEPOSITOR), sharesMinted, "depositor holds the minted shares");
  }

  /// @notice With the fix, the rewards-proportional slice of the depositor's contribution stays
  ///         in the vault as idle balance (instead of being force-fed to the LP at the wrong ratio
  ///         and silently leaking). This is the "fees-count-as-idle" invariant the fix establishes.
  function test_deposit_rewardsRatio_leavesRewardsSliceAsIdle() public {
    (
      SharedVault rv,
      MockERC20 tA,
      MockERC20 tB,
      ,
      MockERC721 nfpm,
      uint256 tokenId,
      MockRewardsAwareStrategy strat
    ) = _setupVaultWithRewardsAwarePosition();

    uint256 idleABefore = tA.balanceOf(address(rv));
    uint256 idleBBefore = tB.balanceOf(address(rv));

    tA.mint(DEPOSITOR, 30e18);
    tB.mint(DEPOSITOR, 80e18);
    vm.startPrank(DEPOSITOR);
    tA.approve(address(rv), type(uint256).max);
    tB.approve(address(rv), type(uint256).max);
    uint256[4] memory amounts = [uint256(30e18), uint256(80e18), uint256(0), uint256(0)];
    rv.deposit(amounts, 0);
    vm.stopPrank();

    // Of the 30 A pulled in, 15 went to the LP and 15 should have stayed idle (the rewards slice).
    // Symmetrically for B: 80 pulled, 35 to LP, 45 stays idle.
    assertEq(tA.balanceOf(address(rv)), idleABefore + 30e18 - 15e18, "rewards-slice of tokenA stays idle in vault");
    assertEq(tB.balanceOf(address(rv)), idleBBefore + 80e18 - 35e18, "rewards-slice of tokenB stays idle in vault");

    // And the LP position's principal grew by exactly the 3:7 top-up. MockLPPool tracks actual
    // balances separately from the virtual rewards, so its balance reflects principal-only.
    MockLPPool lpPool = MockLPPool(strat.lpPool());
    (uint256 poolA, uint256 poolB) = lpPool.getAmounts(address(nfpm), tokenId);
    assertEq(poolA, 30e18 + 15e18, "pool principal grew by 15 A at 3:7 ratio");
    assertEq(poolB, 70e18 + 35e18, "pool principal grew by 35 B at 3:7 ratio");
  }

  /// @notice Direct counter-proof: if we feed the strategy the "buggy" totals-ratio top-up amounts
  ///         (20:40 instead of 15:35) through the same slippage-checked path, the pool rejects them
  ///         as off-ratio. This pins down *why* the fix is needed — the pre-fix amounts can't clear
  ///         the `amount*Min` bar when principal and rewards ratios diverge.
  function test_depositProportional_withBuggyTotalsRatio_revertsUnderSlippageCheck() public {
    // Arrange: the mock strategy does not need to be registered on a vault — we call its
    // depositProportional directly to simulate what the pre-fix SharedVault would have sent.
    MockLPPool pool = new MockLPPool();
    DepositProportionalRecorder recorder = new DepositProportionalRecorder();
    MockRewardsAwareStrategy strat = new MockRewardsAwareStrategy(
      address(pool),
      address(recorder),
      30e18,
      70e18,
      10e18,
      10e18
    );

    // Seed the pool with principal so the ratio-consumption math in depositProportional lines up
    // with the registered position's principal slot.
    MockERC20 tA = new MockERC20("A", "A");
    MockERC20 tB = new MockERC20("B", "B");
    tA.mint(address(this), 1000e18);
    tB.mint(address(this), 1000e18);
    tA.transfer(address(pool), 30e18);
    tB.transfer(address(pool), 70e18);
    MockERC721 nfpm = new MockERC721();
    uint256 tokenId = 42;
    pool.deposit(address(nfpm), tokenId, address(tA), address(tB), 30e18, 70e18);

    // Act + Assert: 1% slippage tolerance is not enough to cover the off-ratio deficit on the A side.
    // The revert happens BEFORE any token transfer, so no balance setup is needed for this call.
    //   consumed0 = min(20, 40 * 30/70) ≈ 17.14e18
    //   min0     = 20 * 0.99             = 19.8e18    →  17.14 < 19.8  → revert.
    vm.expectRevert(bytes("OffRatioDeposit"));
    strat.depositProportional(address(nfpm), tokenId, 20e18, 40e18, uint16(100));

    // Contrast: the principal-ratio amounts clear the same slippage check cleanly. This call
    // DOES reach the token-transfer step, so the strategy must hold the exact consumed amounts
    // (called directly, msg.sender == strat, so transfers originate from strat's own balance).
    tA.transfer(address(strat), 15e18);
    tB.transfer(address(strat), 35e18);
    strat.depositProportional(address(nfpm), tokenId, 15e18, 35e18, uint16(100));
  }
}
