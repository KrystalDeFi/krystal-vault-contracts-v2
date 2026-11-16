// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {
  INonfungiblePositionManager as INFPM
} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface ILivenessToken {
  function transfer(address to, uint256 amount) external returns (bool);

  function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title Uniswap-V3-shaped pool for the liveness harness
/// @notice A single pool at a settable price with zero fee growth, so a position's value is its principal plus
///         `tokensOwed`. Exposes exactly what SharedV3Strategy reads: `slot0`, `ticks` and the global fee growth.
contract LivenessV3Pool {
  uint160 public sqrtPriceX96;
  int24 public tick;

  function setPrice(uint160 sqrtPrice, int24 currentTick) external {
    sqrtPriceX96 = sqrtPrice;
    tick = currentTick;
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

contract LivenessV3Factory {
  address public immutable pool;

  constructor(address pool_) {
    pool = pool_;
  }

  function getPool(address, address, uint24) external view returns (address) {
    return pool;
  }
}

/// @title Uniswap-V3-shaped position manager for the liveness harness
/// @notice Liquidity math follows Uniswap V3: `mint` / `increaseLiquidity` turn the desired amounts into liquidity with
///         `LiquidityAmounts.getLiquidityForAmounts`, pull the `SqrtPriceMath` amounts rounded UP and check them
///         against the minimums ("Price slippage check"); a zero-liquidity add reverts with empty data, like
///         `UniswapV3Pool.mint`. `decreaseLiquidity` owes the amounts rounded DOWN and `collect` pays what is owed.
///         Tokens only enter through adds and only leave through collects, so the manager always holds what it owes.
/// @dev    Small and deterministic on purpose: the mock invariant driver and Echidna run positions at a chosen price.
contract LivenessV3Nfpm {
  address public immutable token0;
  address public immutable token1;
  uint24 public immutable fee;
  LivenessV3Pool public immutable pool;
  LivenessV3Factory internal immutable factoryContract;

  struct Pos {
    address owner;
    address approved;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint128 owed0;
    uint128 owed1;
  }

  mapping(uint256 => Pos) internal posData;
  uint256 public nextId = 1;

  constructor(address token0_, address token1_, uint24 fee_) {
    token0 = token0_;
    token1 = token1_;
    fee = fee_;
    pool = new LivenessV3Pool();
    factoryContract = new LivenessV3Factory(address(pool));
  }

  function factory() external view returns (address) {
    return address(factoryContract);
  }

  function ownerOf(uint256 tokenId) external view returns (address owner) {
    owner = posData[tokenId].owner;
    require(owner != address(0), "Invalid token ID");
  }

  function approve(address to, uint256 tokenId) external {
    require(msg.sender == posData[tokenId].owner, "Not approved");
    posData[tokenId].approved = to;
  }

  function transferFrom(address from, address to, uint256 tokenId) public {
    Pos storage p = posData[tokenId];
    require(p.owner == from && to != address(0), "Invalid transfer");
    require(msg.sender == from || msg.sender == p.approved, "Not approved");
    p.owner = to;
    p.approved = address(0);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    transferFrom(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
    transferFrom(from, to, tokenId);
  }

  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    Pos memory p = posData[tokenId];
    require(p.owner != address(0), "Invalid token ID");
    return (0, address(0), token0, token1, fee, p.tickLower, p.tickUpper, p.liquidity, 0, 0, p.owed0, p.owed1);
  }

  function mint(INFPM.MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    require(params.token0 == token0 && params.token1 == token1 && params.fee == fee, "Invalid pool");
    require(
      params.tickLower < params.tickUpper && params.tickLower >= TickMath.MIN_TICK
        && params.tickUpper <= TickMath.MAX_TICK,
      "Invalid ticks"
    );
    require(params.recipient != address(0), "Invalid recipient");
    tokenId = nextId++;
    posData[tokenId] = Pos(params.recipient, address(0), params.tickLower, params.tickUpper, 0, 0, 0);
    (liquidity, amount0, amount1) =
      _addLiquidity(tokenId, params.amount0Desired, params.amount1Desired, params.amount0Min, params.amount1Min);
  }

  function increaseLiquidity(INFPM.IncreaseLiquidityParams calldata params)
    external
    payable
    returns (uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    require(posData[params.tokenId].owner != address(0), "Invalid token ID");
    (liquidity, amount0, amount1) = _addLiquidity(
      params.tokenId, params.amount0Desired, params.amount1Desired, params.amount0Min, params.amount1Min
    );
  }

  function decreaseLiquidity(INFPM.DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1)
  {
    Pos storage p = posData[params.tokenId];
    require(msg.sender == p.owner || msg.sender == p.approved, "Not approved");
    require(params.liquidity > 0 && p.liquidity >= params.liquidity);
    (amount0, amount1) = _amountsForLiquidity(params.tokenId, params.liquidity, false);
    require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");
    p.liquidity -= params.liquidity;
    p.owed0 += uint128(amount0);
    p.owed1 += uint128(amount1);
  }

  function collect(INFPM.CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
    Pos storage p = posData[params.tokenId];
    require(msg.sender == p.owner || msg.sender == p.approved, "Not approved");
    amount0 = params.amount0Max > p.owed0 ? p.owed0 : params.amount0Max;
    amount1 = params.amount1Max > p.owed1 ? p.owed1 : params.amount1Max;
    p.owed0 -= uint128(amount0);
    p.owed1 -= uint128(amount1);
    address to = params.recipient == address(0) ? address(this) : params.recipient;
    if (amount0 > 0) require(ILivenessToken(token0).transfer(to, amount0), "ST");
    if (amount1 > 0) require(ILivenessToken(token1).transfer(to, amount1), "ST");
  }

  function _addLiquidity(uint256 tokenId, uint256 amount0Desired, uint256 amount1Desired, uint256 min0, uint256 min1)
    internal
    returns (uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    Pos storage p = posData[tokenId];
    liquidity = LiquidityAmounts.getLiquidityForAmounts(
      pool.sqrtPriceX96(),
      TickMath.getSqrtRatioAtTick(p.tickLower),
      TickMath.getSqrtRatioAtTick(p.tickUpper),
      amount0Desired,
      amount1Desired
    );
    require(liquidity > 0); // UniswapV3Pool.mint `require(amount > 0)`: empty revert data
    (amount0, amount1) = _amountsForLiquidity(tokenId, liquidity, true);
    require(amount0 >= min0 && amount1 >= min1, "Price slippage check");
    if (amount0 > 0) require(ILivenessToken(token0).transferFrom(msg.sender, address(this), amount0), "STF");
    if (amount1 > 0) require(ILivenessToken(token1).transferFrom(msg.sender, address(this), amount1), "STF");
    p.liquidity += liquidity;
  }

  function _amountsForLiquidity(uint256 tokenId, uint128 liquidity, bool roundUp)
    internal
    view
    returns (uint256 amount0, uint256 amount1)
  {
    uint160 sqrtPrice = pool.sqrtPriceX96();
    uint160 sqrtLower = TickMath.getSqrtRatioAtTick(posData[tokenId].tickLower);
    uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(posData[tokenId].tickUpper);
    if (sqrtPrice <= sqrtLower) {
      amount0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
    } else if (sqrtPrice < sqrtUpper) {
      amount0 = SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtUpper, liquidity, roundUp);
      amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPrice, liquidity, roundUp);
    } else {
      amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
    }
  }
}
