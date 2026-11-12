// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Regression test for GHSA-7gvj-vm6c-xxqf: a native-ETH deposit into a vault that holds a position no
// longer reverts. Vault, strategy and beacon proxy are the real contracts; the AMM is a mock with Uniswap-V3
// rounding (mint rounds amounts up, burn rounds down).

import { Test } from "forge-std/Test.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedStrategyBeacon } from "../../contracts/shared-vault/strategies/SharedStrategyBeacon.sol";
import { SharedStrategyProxy } from "../../contracts/shared-vault/strategies/SharedStrategyProxy.sol";

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

contract RgWETH is RgERC20 {
  constructor() RgERC20("WETH", 18) { }

  function deposit() external payable {
    balanceOf[msg.sender] += msg.value;
  }

  function withdraw(uint256 a) external {
    balanceOf[msg.sender] -= a;
    (bool ok,) = msg.sender.call{ value: a }("");
    require(ok, "eth");
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

contract GHSA_7gvj_UnitRegression is Test {
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

  // ═════════ GHSA-7gvj: native-ETH deposit into a vault that holds a position ═════════

  function test_GHSA_7gvj_nativeEthDeposit_withLivePosition_matchesWethDeposit_andRefundsExcess() public {
    RgWETH weth = new RgWETH();
    RgERC20 usdc = new RgERC20("USDC", 18);
    RgV3Nfpm nfpm = new RgV3Nfpm(RgERC20(address(weth)), usdc);
    weth.mint(address(nfpm), 1_000_000e18);
    usdc.mint(address(nfpm), 1_000_000e18);

    // Production topology: vault --delegatecall--> SharedStrategyProxy --delegatecall--> SharedV3Strategy.
    SharedV3Strategy impl = new SharedV3Strategy(address(0xBEEF));
    SharedStrategyBeacon beacon = new SharedStrategyBeacon(address(impl), address(this));
    SharedStrategyProxy proxy = new SharedStrategyProxy(address(beacon));
    SharedConfigManager cm = _cm(_one(address(proxy)), _one(address(nfpm)));
    SharedVault v = _vault("Rg7gvj", address(weth), address(usdc), cm, address(weth));

    _fundApprove(alice, RgERC20(address(weth)), 100e18, address(v));
    _fundApprove(alice, usdc, 100e18, address(v));
    vm.prank(alice);
    v.deposit([uint256(10e18), uint256(10e18), 0, 0], 0, 0);
    uint256 id = nfpm.mintExternal(operator, -600, 600, 1e20); // live, in-range position
    _recover(v, nfpm, id, address(proxy));
    uint128 liqBefore = _liquidity(nfpm, id);

    // Bob offers 2 ETH + 1 USDC. The vault needs about 1 WETH per USDC, so about 1 ETH is excess.
    uint256[4] memory amts = [uint256(2e18), uint256(1e18), 0, 0];
    vm.deal(bob, 10e18);
    _fundApprove(bob, usdc, 100e18, address(v));
    uint256 snap = vm.snapshotState();

    uint256 ethBefore = bob.balance;
    vm.prank(bob);
    uint256 sharesEth = v.deposit{ value: 2e18 }(amts, 0, 0);
    uint256 ethSpent = ethBefore - bob.balance;
    assertGt(_liquidity(nfpm, id), liqBefore, "position topped up: the strategy ran with msg.value > 0");
    assertGt(ethSpent, 0, "ETH was used");
    assertLt(ethSpent, 2e18, "excess ETH refunded");
    assertEq(address(v).balance, 0, "no raw ETH left in the vault");

    // The same deposit paid in WETH prices identically.
    vm.revertToState(snap);
    _fundApprove(bob, RgERC20(address(weth)), 2e18, address(v));
    uint256 wethBefore = weth.balanceOf(bob);
    vm.prank(bob);
    uint256 sharesWeth = v.deposit(amts, 0, 0);
    assertEq(sharesEth, sharesWeth, "ETH and WETH deposits mint the same shares");
    assertEq(ethSpent, wethBefore - weth.balanceOf(bob), "ETH spent equals WETH pulled");
  }
}
