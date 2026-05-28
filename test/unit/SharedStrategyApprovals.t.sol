// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ---------------------------------------------------------------------------
// Minimal ERC20 that records the last approve() call so tests can assert
// that approvals are cleared to zero after depositProportional.
// ---------------------------------------------------------------------------
contract SpyERC20 {
  string public name;
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name) { name = _name; symbol = _name; }

  function mint(address to, uint256 amount) external { balanceOf[to] += amount; }

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// ---------------------------------------------------------------------------
// Mock NFPM (Uniswap V3 style) — returns token addresses from positions()
// and simulates increaseLiquidity by consuming HALF the approved amount
// (exercising the residual-allowance scenario).
// ---------------------------------------------------------------------------
contract MockV3Nfpm {
  address public t0;
  address public t1;

  constructor(address _t0, address _t1) { t0 = _t0; t1 = _t1; }

  function positions(uint256) external view returns (
    uint96, address, address token0, address token1, uint24, int24, int24,
    uint128, uint256, uint256, uint128, uint128
  ) {
    return (0, address(0), t0, t1, 500, -887200, 887200, 1e18, 0, 0, 0, 0);
  }

  struct IncreaseLiquidityParams {
    uint256 tokenId;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  // Consumes exactly HALF of each desired amount to leave a residual allowance.
  function increaseLiquidity(IncreaseLiquidityParams calldata p)
    external returns (uint128 liquidity, uint256 a0, uint256 a1)
  {
    uint256 half0 = p.amount0Desired / 2;
    uint256 half1 = p.amount1Desired / 2;
    if (half0 > 0) IERC20(t0).transferFrom(msg.sender, address(this), half0);
    if (half1 > 0) IERC20(t1).transferFrom(msg.sender, address(this), half1);
    return (1e15, half0, half1);
  }
}

// ---------------------------------------------------------------------------
// Mock Aerodrome NFPM — same shape but uses tickSpacing instead of fee.
// ---------------------------------------------------------------------------
contract MockAerodromNfpm {
  address public t0;
  address public t1;

  constructor(address _t0, address _t1) { t0 = _t0; t1 = _t1; }

  // Aerodrome positions() returns tickSpacing at index 4, not fee
  function positions(uint256) external view returns (
    uint96, address, address token0, address token1, int24 tickSpacing,
    int24, int24, uint128, uint256, uint256, uint128, uint128
  ) {
    return (0, address(0), t0, t1, 10, -887200, 887200, 1e18, 0, 0, 0, 0);
  }

  struct IncreaseLiquidityParams {
    uint256 tokenId;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  function increaseLiquidity(IncreaseLiquidityParams calldata p)
    external returns (uint128 liquidity, uint256 a0, uint256 a1)
  {
    uint256 half0 = p.amount0Desired / 2;
    uint256 half1 = p.amount1Desired / 2;
    if (half0 > 0) IERC20(t0).transferFrom(msg.sender, address(this), half0);
    if (half1 > 0) IERC20(t1).transferFrom(msg.sender, address(this), half1);
    return (1e15, half0, half1);
  }
}

// ---------------------------------------------------------------------------
// Vault harness: implements the subset of ISharedVault that strategies read
// via ISharedVault(address(this)) in the delegatecall context.
// Delegatecalls to a strategy so that address(this) == vault harness.
// ---------------------------------------------------------------------------
contract StrategyVaultHarness {
  ISharedConfigManager public configManager;
  mapping(address => bool) private _vaultTokens;

  constructor(address cm) { configManager = ISharedConfigManager(cm); }

  function addVaultToken(address token) external { _vaultTokens[token] = true; }

  function isVaultToken(address token) external view returns (bool) { return _vaultTokens[token]; }

  function callDepositProportional(
    address strategy,
    address nfpm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1
  ) external {
    (bool ok, bytes memory err) = strategy.delegatecall(
      abi.encodeCall(ISharedStrategy.depositProportional, (nfpm, tokenId, amount0, amount1, 0))
    );
    if (!ok) {
      assembly { revert(add(err, 32), mload(err)) }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
contract SharedStrategyApprovalsTest is Test {
  SharedConfigManager internal cm;
  SpyERC20 internal tA;
  SpyERC20 internal tB;

  function _setupConfigManager(address nfpm) internal returns (SharedConfigManager) {
    SharedConfigManager c = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = nfpm;
    c.initialize(address(this), new address[](0), new address[](0), address(0xFEE), 0, nfpms, new address[](0));
    return c;
  }

  // -------------------------------------------------------------------------
  // SharedV3Strategy.depositProportional — NFPM allowances zeroed after call
  // -------------------------------------------------------------------------

  function test_v3_depositProportional_clears_nfpm_approvals() public {
    tA = new SpyERC20("TA");
    tB = new SpyERC20("TB");
    MockV3Nfpm nfpm = new MockV3Nfpm(address(tA), address(tB));

    cm = _setupConfigManager(address(nfpm));

    // V3Strategy with dummy swap router (not called in depositProportional)
    SharedV3Strategy strategy = new SharedV3Strategy(address(1), address(1));

    StrategyVaultHarness vault = new StrategyVaultHarness(address(cm));
    vault.addVaultToken(address(tA));
    vault.addVaultToken(address(tB));

    uint256 amount = 100e18;
    tA.mint(address(vault), amount);
    tB.mint(address(vault), amount);

    vault.callDepositProportional(address(strategy), address(nfpm), 1, amount, amount);

    assertEq(tA.allowance(address(vault), address(nfpm)), 0, "token0 approval must be cleared");
    assertEq(tB.allowance(address(vault), address(nfpm)), 0, "token1 approval must be cleared");
  }

  function test_v3_depositProportional_clears_approvals_when_only_token0_nonzero() public {
    tA = new SpyERC20("TA");
    tB = new SpyERC20("TB");
    MockV3Nfpm nfpm = new MockV3Nfpm(address(tA), address(tB));

    cm = _setupConfigManager(address(nfpm));
    SharedV3Strategy strategy = new SharedV3Strategy(address(1), address(1));

    StrategyVaultHarness vault = new StrategyVaultHarness(address(cm));
    vault.addVaultToken(address(tA));
    vault.addVaultToken(address(tB));

    tA.mint(address(vault), 100e18);

    // Only amount0 > 0; amount1 == 0 should not set or need clearing
    vault.callDepositProportional(address(strategy), address(nfpm), 1, 100e18, 0);

    assertEq(tA.allowance(address(vault), address(nfpm)), 0, "token0 approval must be cleared");
    assertEq(tB.allowance(address(vault), address(nfpm)), 0, "token1 had no approval, stays zero");
  }

  // -------------------------------------------------------------------------
  // SharedAerodromeStrategy.depositProportional — same assertion
  // -------------------------------------------------------------------------

  function test_aerodrome_depositProportional_clears_nfpm_approvals() public {
    tA = new SpyERC20("TA");
    tB = new SpyERC20("TB");
    MockAerodromNfpm nfpm = new MockAerodromNfpm(address(tA), address(tB));

    cm = _setupConfigManager(address(nfpm));

    SharedAerodromeStrategy strategy = new SharedAerodromeStrategy(address(1), address(1));

    StrategyVaultHarness vault = new StrategyVaultHarness(address(cm));
    vault.addVaultToken(address(tA));
    vault.addVaultToken(address(tB));

    uint256 amount = 100e18;
    tA.mint(address(vault), amount);
    tB.mint(address(vault), amount);

    vault.callDepositProportional(address(strategy), address(nfpm), 1, amount, amount);

    assertEq(tA.allowance(address(vault), address(nfpm)), 0, "token0 approval must be cleared");
    assertEq(tB.allowance(address(vault), address(nfpm)), 0, "token1 approval must be cleared");
  }
}
