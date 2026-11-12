// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Regression tests for GHSA-8mr4-8944-7fqq: SharedV3Strategy.depositProportional skips zero-liquidity
// slices and quotes its slippage floor from the liquidity it can add. Vault and strategy are the real
// contracts; the AMM is a mock with Uniswap-V3 rounding (mint rounds amounts up, burn rounds down, a
// zero-liquidity mint reverts with empty data like UniswapV3Pool).

import { Test } from "forge-std/Test.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";

// ───────────────────────────── mocks ─────────────────────────────

uint160 constant RG_SQRT_1_1 = 79_228_162_514_264_337_593_543_950_336;

contract RgERC20 {
  string public name;
  string public symbol;
  uint8 public decimals;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory s, uint8 d) {
    name = s;
    symbol = s;
    decimals = d;
  }

  function mint(address to, uint256 a) external {
    balanceOf[to] += a;
  }

  function approve(address sp, uint256 a) external returns (bool) {
    allowance[msg.sender][sp] = a;
    return true;
  }

  function transfer(address to, uint256 a) external returns (bool) {
    balanceOf[msg.sender] -= a;
    balanceOf[to] += a;
    return true;
  }

  function transferFrom(address f, address to, uint256 a) external returns (bool) {
    if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
    balanceOf[f] -= a;
    balanceOf[to] += a;
    return true;
  }
}

contract RgV3Pool {
  uint160 public sqrtPriceX96 = RG_SQRT_1_1;
  int24 public tick;

  function setPrice(uint160 p, int24 t) external {
    sqrtPriceX96 = p;
    tick = t;
  }

  function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
    return (sqrtPriceX96, tick, 0, 0, 0, 0, true);
  }

  function feeGrowthGlobal0X128() external pure returns (uint256) {
    return 0;
  }

  function feeGrowthGlobal1X128() external pure returns (uint256) {
    return 0;
  }

  function ticks(int24) external pure returns (uint128, int128, uint256, uint256, int56, uint160, uint32, bool) {
    return (0, 0, 0, 0, 0, 0, 0, true);
  }
}

contract RgV3Factory {
  address public immutable pool;

  constructor(address p) {
    pool = p;
  }

  function getPool(address, address, uint24) external view returns (address) {
    return pool;
  }
}

contract RgV3Nfpm {
  RgERC20 public immutable token0;
  RgERC20 public immutable token1;
  RgV3Pool public immutable pool;
  RgV3Factory public immutable factoryContract;

  struct Pos {
    address owner;
    address approved;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint128 owed0;
    uint128 owed1;
  }

  mapping(uint256 => Pos) public posData;
  uint256 public nextId = 1;

  constructor(RgERC20 t0, RgERC20 t1) {
    token0 = t0;
    token1 = t1;
    pool = new RgV3Pool();
    factoryContract = new RgV3Factory(address(pool));
  }

  function factory() external view returns (address) {
    return address(factoryContract);
  }

  function ownerOf(uint256 id) external view returns (address) {
    return posData[id].owner;
  }

  function approve(address to, uint256 id) external {
    require(msg.sender == posData[id].owner, "not owner");
    posData[id].approved = to;
  }

  function transferFrom(address from, address to, uint256 id) public {
    Pos storage p = posData[id];
    require(p.owner == from, "wrong from");
    require(msg.sender == from || msg.sender == p.approved, "not approved");
    p.owner = to;
    p.approved = address(0);
  }

  function safeTransferFrom(address from, address to, uint256 id) external {
    transferFrom(from, to, id);
  }

  function mintExternal(address to, int24 tl, int24 tu, uint128 liq) external returns (uint256 id) {
    id = nextId++;
    posData[id] = Pos(to, address(0), tl, tu, liq, 0, 0);
  }

  function positions(uint256 id)
    external
    view
    returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    Pos memory p = posData[id];
    return (
      0, address(0), address(token0), address(token1), 500, p.tickLower, p.tickUpper, p.liquidity, 0, 0, p.owed0, p.owed1
    );
  }

  function _range(uint256 id) internal view returns (uint160 sp, uint160 sa, uint160 sb) {
    sp = pool.sqrtPriceX96();
    sa = TickMath.getSqrtRatioAtTick(posData[id].tickLower);
    sb = TickMath.getSqrtRatioAtTick(posData[id].tickUpper);
  }

  function _amounts(uint160 sp, uint160 sa, uint160 sb, uint128 l, bool up)
    internal
    pure
    returns (uint256 a0, uint256 a1)
  {
    if (sp <= sa) {
      a0 = SqrtPriceMath.getAmount0Delta(sa, sb, l, up);
    } else if (sp < sb) {
      a0 = SqrtPriceMath.getAmount0Delta(sp, sb, l, up);
      a1 = SqrtPriceMath.getAmount1Delta(sa, sp, l, up);
    } else {
      a1 = SqrtPriceMath.getAmount1Delta(sa, sb, l, up);
    }
  }

  function increaseLiquidity(INFPM.IncreaseLiquidityParams calldata params)
    external
    payable
    returns (uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    (uint160 sp, uint160 sa, uint160 sb) = _range(params.tokenId);
    liquidity = LiquidityAmounts.getLiquidityForAmounts(sp, sa, sb, params.amount0Desired, params.amount1Desired);
    require(liquidity > 0); // UniswapV3Pool.mint `require(amount > 0)`: empty revert data
    (amount0, amount1) = _amounts(sp, sa, sb, liquidity, true);
    require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");
    if (amount0 > 0) token0.transferFrom(msg.sender, address(this), amount0);
    if (amount1 > 0) token1.transferFrom(msg.sender, address(this), amount1);
    posData[params.tokenId].liquidity += liquidity;
  }

  function decreaseLiquidity(INFPM.DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1)
  {
    Pos storage p = posData[params.tokenId];
    require(params.liquidity > 0 && p.liquidity >= params.liquidity);
    (uint160 sp, uint160 sa, uint160 sb) = _range(params.tokenId);
    (amount0, amount1) = _amounts(sp, sa, sb, params.liquidity, false);
    p.liquidity -= params.liquidity;
    p.owed0 += uint128(amount0);
    p.owed1 += uint128(amount1);
  }

  function collect(INFPM.CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
    Pos storage p = posData[params.tokenId];
    amount0 = params.amount0Max > p.owed0 ? p.owed0 : params.amount0Max;
    amount1 = params.amount1Max > p.owed1 ? p.owed1 : params.amount1Max;
    p.owed0 -= uint128(amount0);
    p.owed1 -= uint128(amount1);
    address to = params.recipient == address(0) ? address(this) : params.recipient;
    if (amount0 > 0) token0.transfer(to, amount0);
    if (amount1 > 0) token1.transfer(to, amount1);
  }
}

// ───────────────────────────── tests ─────────────────────────────

contract GHSA_8mr4_UnitRegression is Test {
  address internal vaultOwner = makeAddr("rgVaultOwner");
  address internal operator = makeAddr("rgOperator");
  address internal feeRecipient = makeAddr("rgFeeRecipient");
  address internal alice = makeAddr("rgAlice");
  address internal bob = makeAddr("rgBob");

  function _one(address a) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
  }

  function _cm(address[] memory targets, address[] memory nfpms) internal returns (SharedConfigManager cm) {
    cm = new SharedConfigManager();
    cm.initialize(
      address(this), targets, new address[](0), feeRecipient, 0, nfpms, new address[](0), new address[](0)
    );
  }

  function _vault(string memory name, address t0, address t1, SharedConfigManager cm, address weth_)
    internal
    returns (SharedVault v)
  {
    v = new SharedVault();
    v.initialize(
      name, [t0, t1, address(0), address(0)], [uint256(0), 0, 0, 0], vaultOwner, operator, address(cm), weth_, 0
    );
  }

  function _fundApprove(address who, RgERC20 t, uint256 amt, address spender) internal {
    t.mint(who, amt);
    vm.prank(who);
    t.approve(spender, type(uint256).max);
  }

  function _recover(SharedVault v, RgV3Nfpm nfpm, uint256 id, address strat) internal {
    vm.startPrank(operator);
    nfpm.approve(address(v), id);
    v.recoverPosition(address(nfpm), id, strat, address(nfpm.token0()), address(nfpm.token1()));
    vm.stopPrank();
  }

  function _liquidity(RgV3Nfpm nfpm, uint256 id) internal view returns (uint128 liq) {
    (,,,,,,, liq,,,,) = nfpm.positions(id);
  }

  // ═════════ GHSA-8mr4: SharedV3Strategy.depositProportional ═════════

  function _v3World()
    internal
    returns (RgERC20 weth, RgERC20 usdc, RgV3Nfpm nfpm, SharedV3Strategy strat, SharedConfigManager cm)
  {
    weth = new RgERC20("WETH", 18);
    usdc = new RgERC20("USDC", 6);
    nfpm = new RgV3Nfpm(weth, usdc);
    weth.mint(address(nfpm), 1_000_000e18);
    usdc.mint(address(nfpm), 1_000_000e18);
    strat = new SharedV3Strategy(address(0xBEEF));
    cm = _cm(_one(address(strat)), _one(address(nfpm)));
  }

  /// A slice worth zero liquidity (dust position) stays idle instead of reverting the deposit in the pool's mint.
  function test_GHSA_8mr4_zeroLiquiditySlice_staysIdle_andDepositSucceeds() public {
    (RgERC20 weth, RgERC20 usdc, RgV3Nfpm nfpm, SharedV3Strategy strat, SharedConfigManager cm) = _v3World();
    nfpm.pool().setPrice(TickMath.getSqrtRatioAtTick(-200_000), -200_000);
    SharedVault v = _vault("Rg8mr4A", address(weth), address(usdc), cm, address(0));
    _fundApprove(alice, weth, 1_000e18, address(v));
    _fundApprove(alice, usdc, 1_000_000e6, address(v));
    vm.prank(alice);
    v.deposit([uint256(100e18), uint256(200_000e6), 0, 0], 0, 0);

    uint256 id = nfpm.mintExternal(operator, -199_900, -199_800, 20); // dust, below range: token0 only
    _recover(v, nfpm, id, address(strat));
    (uint256 p0,) = strat.getPositionPrincipalAmounts(address(nfpm), id);
    assertGt(p0, 0, "dust position has principal");

    _fundApprove(bob, weth, 1_000e18, address(v));
    _fundApprove(bob, usdc, 10_000_000e6, address(v));
    uint256 supplyBefore = v.totalSupply();
    vm.prank(bob);
    uint256 shares = v.deposit([uint256(1e18), uint256(2_001e6), 0, 0], 50, 0);
    assertApproxEqRel(shares, supplyBefore / 100, 1e15, "fair shares for a 1% deposit");
    assertEq(_liquidity(nfpm, id), 20, "zero-liquidity slice was not added; it stays idle");
  }

  /// Range-edge position (one principal side is ~15 wei): a deposit with a non-zero slippage floor succeeds at an
  /// unchanged price, because the floor is quoted from the liquidity added, not from the raw amounts.
  function test_GHSA_8mr4_rangeEdgePosition_depositWithSlippage_succeedsAtConstantPrice() public {
    (RgERC20 weth, RgERC20 usdc, RgV3Nfpm nfpm, SharedV3Strategy strat, SharedConfigManager cm) = _v3World();
    uint128 L = 4e18;
    uint160 sqrtA = TickMath.getSqrtRatioAtTick(0);
    nfpm.pool().setPrice(sqrtA + uint160((uint256(155) * RG_SQRT_1_1) / (10 * uint256(L))), 0);

    uint256 probeId = nfpm.mintExternal(address(this), 0, 6000, L);
    (uint256 p0, uint256 p1) = strat.getPositionPrincipalAmounts(address(nfpm), probeId);
    assertGt(p0, 1e17);
    assertLt(p1, 20, "the token1 side is a handful of wei");

    SharedVault v = _vault("Rg8mr4B", address(weth), address(usdc), cm, address(0));
    _fundApprove(alice, weth, 10e18, address(v));
    _fundApprove(alice, usdc, 10e6, address(v));
    vm.prank(alice);
    v.deposit([p0, p1, 0, 0], 0, 0);
    vm.startPrank(address(v)); // capital deployed: idle -> LP
    weth.transfer(address(nfpm), p0);
    usdc.transfer(address(nfpm), p1);
    vm.stopPrank();
    uint256 id = nfpm.mintExternal(operator, 0, 6000, L);
    _recover(v, nfpm, id, address(strat));

    _fundApprove(bob, weth, 10e18, address(v));
    _fundApprove(bob, usdc, 10e6, address(v));
    uint256 supplyBefore = v.totalSupply();
    vm.prank(bob);
    uint256 shares = v.deposit([p0 / 2 + 1, uint256(10), 0, 0], 50, 0); // 0.5% slippage, price unchanged
    assertApproxEqRel(shares, supplyBefore / 2, 1e15, "fair shares");
    assertGt(_liquidity(nfpm, id), L, "the slice was added to the position");
  }
}
