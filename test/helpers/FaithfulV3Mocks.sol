// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Tick as V3Tick } from "@uniswap/v3-core/contracts/libraries/Tick.sol";
import { Position as V3Position } from "@uniswap/v3-core/contracts/libraries/Position.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { FixedPoint128 } from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {
  INonfungiblePositionManager as INFPM
} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {
  INonfungiblePositionManager as IAeroNfpm
} from "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

// Faithful mocks of the NFT-position-manager families the shared strategies drive: Uniswap V3
// (v3-core UniswapV3Pool + v3-periphery NonfungiblePositionManager) and Aerodrome Slipstream (lib/slipstream
// CLPool + NonfungiblePositionManager). One pool core and one NFPM core carry the shared behaviour; thin skins
// expose each protocol's ABI (fee vs tickSpacing keys, slot0/ticks shapes, revert strings).
//
// Reproduced upstream behaviour (file and function cited at each site):
//   - position liquidity is derived from the desired amounts at the current price, rounded down;
//   - a zero-liquidity add reverts in the pool (`require(amount > 0)`, empty revert data);
//   - minted amounts round up and burned amounts round down;
//   - minimums are checked on the CONSUMED / returned amounts ('Price slippage check', Slipstream "PSC" / "PS");
//   - fee growth accrues into tokensOwed on increase / decrease / collect (collect pokes the pool first), and
//     collect pays principal plus fees, capped by the requested maxima;
//   - the pool holds the tokens; the NFPM pays mints through the mint callback (payer's ERC-20 allowance to the
//     NFPM is required) and only the owner or an approved address can decrease or collect.
// Not modelled: swaps / price moves (tests run at a fixed price; fees are credited the way a swap credits them),
// the oracle, tick bitmaps, protocol fees, Slipstream gauges and staking (unstaked positions only), ETH payments.

/// @dev Interface of the mint callback the pool invokes on its caller (IUniswapV3MintCallback / ICLMintCallback).
interface IFaithfulMintCallback {
  function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external;
}

/// @dev Concentrated-liquidity pool core shared by the Uniswap V3 and Slipstream skins. Position, tick and fee
///      growth bookkeeping is the v3-core `Tick` / `Position` libraries themselves.
abstract contract FaithfulClPoolCore {
  using SafeERC20 for IERC20;
  using V3Tick for mapping(int24 => V3Tick.Info);
  using V3Position for mapping(bytes32 => V3Position.Info);
  using V3Position for V3Position.Info;

  address public immutable token0;
  address public immutable token1;
  int24 public immutable tickSpacing;
  uint128 public immutable maxLiquidityPerTick;

  uint160 internal _sqrtPriceX96;
  int24 internal _tick;
  uint256 public feeGrowthGlobal0X128;
  uint256 public feeGrowthGlobal1X128;
  uint128 public liquidity;
  mapping(int24 => V3Tick.Info) internal _ticks;
  /// @dev UniswapV3Pool.positions(bytes32 key): (liquidity, feeGrowthInside{0,1}LastX128, tokensOwed{0,1}).
  mapping(bytes32 => V3Position.Info) public positions;

  constructor(address _token0, address _token1, int24 _tickSpacing, uint160 initialSqrtPriceX96) {
    require(_token0 < _token1, "token order");
    token0 = _token0;
    token1 = _token1;
    tickSpacing = _tickSpacing;
    maxLiquidityPerTick = V3Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    _sqrtPriceX96 = initialSqrtPriceX96;
    _tick = TickMath.getTickAtSqrtRatio(initialSqrtPriceX96);
  }

  function sqrtPriceX96() external view returns (uint160) {
    return _sqrtPriceX96;
  }

  /// @dev UniswapV3Pool.mint: zero liquidity reverts with empty data; owed amounts round up and are paid through
  ///      the caller's mint callback, after which the pool checks its balances.
  function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
    external
    returns (uint256 amount0, uint256 amount1)
  {
    require(amount > 0);
    (, int256 amount0Int, int256 amount1Int) = _modifyPosition(recipient, tickLower, tickUpper, int128(uint128(amount)));
    amount0 = uint256(amount0Int);
    amount1 = uint256(amount1Int);
    uint256 balance0Before = IERC20(token0).balanceOf(address(this));
    uint256 balance1Before = IERC20(token1).balanceOf(address(this));
    IFaithfulMintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
    if (amount0 > 0) require(balance0Before + amount0 <= IERC20(token0).balanceOf(address(this)), "M0");
    if (amount1 > 0) require(balance1Before + amount1 <= IERC20(token1).balanceOf(address(this)), "M1");
  }

  /// @dev UniswapV3Pool.burn: returned amounts round down and are credited to the position's tokensOwed;
  ///      `amount == 0` is a poke that only syncs fees.
  function burn(int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256 amount0, uint256 amount1) {
    (V3Position.Info storage position, int256 amount0Int, int256 amount1Int) =
      _modifyPosition(msg.sender, tickLower, tickUpper, -int128(uint128(amount)));
    amount0 = uint256(-amount0Int);
    amount1 = uint256(-amount1Int);
    if (amount0 > 0 || amount1 > 0) {
      position.tokensOwed0 += uint128(amount0);
      position.tokensOwed1 += uint128(amount1);
    }
  }

  /// @dev UniswapV3Pool.collect: pays min(requested, owed) from the pool's balance.
  function collect(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount0Requested,
    uint128 amount1Requested
  ) external returns (uint128 amount0, uint128 amount1) {
    V3Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);
    amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
    amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;
    if (amount0 > 0) {
      position.tokensOwed0 -= amount0;
      IERC20(token0).safeTransfer(recipient, amount0);
    }
    if (amount1 > 0) {
      position.tokensOwed1 -= amount1;
      IERC20(token1).safeTransfer(recipient, amount1);
    }
  }

  /// @dev Test hook: credits LP fees the way UniswapV3Pool.swap does for a step that stays at the current price
  ///      (`feeGrowthGlobalX128 += mulDiv(feeAmount, Q128, liquidity)`); the fee tokens are paid in by the caller.
  function accrueSwapFees(uint256 fee0, uint256 fee1) external {
    require(liquidity > 0, "no in-range liquidity");
    if (fee0 > 0) {
      IERC20(token0).safeTransferFrom(msg.sender, address(this), fee0);
      feeGrowthGlobal0X128 += FullMath.mulDiv(fee0, FixedPoint128.Q128, liquidity);
    }
    if (fee1 > 0) {
      IERC20(token1).safeTransferFrom(msg.sender, address(this), fee1);
      feeGrowthGlobal1X128 += FullMath.mulDiv(fee1, FixedPoint128.Q128, liquidity);
    }
  }

  /// @dev Fee growth inside a range as the pool reports it (Tick.getFeeGrowthInside at the current tick).
  function feeGrowthInside(int24 tickLower, int24 tickUpper) public view returns (uint256 inside0, uint256 inside1) {
    return _ticks.getFeeGrowthInside(tickLower, tickUpper, _tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
  }

  /// @dev UniswapV3Pool._modifyPosition: the current tick picks which side(s) the liquidity is worth, signed
  ///      SqrtPriceMath rounds up when adding and down when removing, and in-range changes move active liquidity.
  function _modifyPosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta)
    private
    returns (V3Position.Info storage position, int256 amount0, int256 amount1)
  {
    require(tickLower < tickUpper, "TLU");
    require(tickLower >= TickMath.MIN_TICK, "TLM");
    require(tickUpper <= TickMath.MAX_TICK, "TUM");
    position = _updatePosition(owner, tickLower, tickUpper, liquidityDelta);
    if (liquidityDelta != 0) {
      if (_tick < tickLower) {
        amount0 = SqrtPriceMath.getAmount0Delta(
          TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
        );
      } else if (_tick < tickUpper) {
        amount0 = SqrtPriceMath.getAmount0Delta(_sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta);
        amount1 = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(tickLower), _sqrtPriceX96, liquidityDelta);
        liquidity = liquidityDelta < 0 ? liquidity - uint128(-liquidityDelta) : liquidity + uint128(liquidityDelta);
      } else {
        amount1 = SqrtPriceMath.getAmount1Delta(
          TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
        );
      }
    }
  }

  /// @dev UniswapV3Pool._updatePosition: Tick.update initialises a fresh tick's feeGrowthOutside (growth below the
  ///      current tick is attributed below), Position.update credits accrued fees, emptied ticks are cleared.
  function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta)
    private
    returns (V3Position.Info storage position)
  {
    position = positions.get(owner, tickLower, tickUpper);
    bool flippedLower;
    bool flippedUpper;
    if (liquidityDelta != 0) {
      flippedLower = _ticks.update(
        tickLower,
        _tick,
        liquidityDelta,
        feeGrowthGlobal0X128,
        feeGrowthGlobal1X128,
        0,
        0,
        0,
        false,
        maxLiquidityPerTick
      );
      flippedUpper = _ticks.update(
        tickUpper, _tick, liquidityDelta, feeGrowthGlobal0X128, feeGrowthGlobal1X128, 0, 0, 0, true, maxLiquidityPerTick
      );
    }
    (uint256 inside0, uint256 inside1) =
      _ticks.getFeeGrowthInside(tickLower, tickUpper, _tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
    position.update(liquidityDelta, inside0, inside1);
    if (liquidityDelta < 0) {
      if (flippedLower) _ticks.clear(tickLower);
      if (flippedUpper) _ticks.clear(tickUpper);
    }
  }
}

/// @dev Uniswap V3 pool ABI (v3-core IUniswapV3PoolState.slot0 / ticks).
contract FaithfulUniV3Pool is FaithfulClPoolCore {
  uint24 public immutable fee;

  constructor(address _token0, address _token1, uint24 _fee, int24 _tickSpacing, uint160 sqrtPriceX96)
    FaithfulClPoolCore(_token0, _token1, _tickSpacing, sqrtPriceX96)
  {
    fee = _fee;
  }

  function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
    return (_sqrtPriceX96, _tick, 0, 1, 1, 0, true);
  }

  function ticks(int24 tick) external view returns (uint128, int128, uint256, uint256, int56, uint160, uint32, bool) {
    V3Tick.Info storage info = _ticks[tick];
    return (
      info.liquidityGross,
      info.liquidityNet,
      info.feeGrowthOutside0X128,
      info.feeGrowthOutside1X128,
      info.tickCumulativeOutside,
      info.secondsPerLiquidityOutsideX128,
      info.secondsOutside,
      info.initialized
    );
  }
}

/// @dev Slipstream CLPool ABI (lib/slipstream ICLPoolState.slot0 / ticks: no feeProtocol word, staked and reward
///      fields in ticks — zero here because positions are never staked).
contract FaithfulSlipstreamPool is FaithfulClPoolCore {
  constructor(address _token0, address _token1, int24 _tickSpacing, uint160 sqrtPriceX96)
    FaithfulClPoolCore(_token0, _token1, _tickSpacing, sqrtPriceX96)
  { }

  function slot0() external view returns (uint160, int24, uint16, uint16, uint16, bool) {
    return (_sqrtPriceX96, _tick, 0, 1, 1, true);
  }

  function ticks(int24 tick)
    external
    view
    returns (uint128, int128, int128, uint256, uint256, uint256, int56, uint160, uint32, bool)
  {
    V3Tick.Info storage info = _ticks[tick];
    return (
      info.liquidityGross,
      info.liquidityNet,
      0,
      info.feeGrowthOutside0X128,
      info.feeGrowthOutside1X128,
      0,
      info.tickCumulativeOutside,
      info.secondsPerLiquidityOutsideX128,
      info.secondsOutside,
      info.initialized
    );
  }
}

/// @dev UniswapV3Factory.getPool(tokenA, tokenB, fee), single pool.
contract FaithfulUniV3Factory {
  FaithfulUniV3Pool public immutable pool;

  constructor(FaithfulUniV3Pool _pool) {
    pool = _pool;
  }

  function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
    (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    if (t0 == pool.token0() && t1 == pool.token1() && fee == pool.fee()) return address(pool);
    return address(0);
  }
}

/// @dev Slipstream CLFactory.getPool(tokenA, tokenB, tickSpacing), single pool.
contract FaithfulSlipstreamFactory {
  FaithfulSlipstreamPool public immutable pool;

  constructor(FaithfulSlipstreamPool _pool) {
    pool = _pool;
  }

  function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address) {
    (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    if (t0 == pool.token0() && t1 == pool.token1() && tickSpacing == pool.tickSpacing()) return address(pool);
    return address(0);
  }
}

/// @dev NonfungiblePositionManager core shared by the Uniswap V3 and Slipstream skins. The position ledger
///      (per-token feeGrowthInsideLast / tokensOwed snapshots) follows v3-periphery NonfungiblePositionManager.
abstract contract FaithfulNfpmCore is ERC721, IFaithfulMintCallback {
  using SafeERC20 for IERC20;

  struct NfpmPosition {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
  }

  FaithfulClPoolCore internal immutable _pool;
  address public immutable factory;
  address internal immutable _token0;
  address internal immutable _token1;

  mapping(uint256 => NfpmPosition) internal _positions;
  uint256 public nextTokenId = 1;

  constructor(FaithfulClPoolCore pool_, address factory_, string memory name_) ERC721(name_, name_) {
    _pool = pool_;
    factory = factory_;
    _token0 = pool_.token0();
    _token1 = pool_.token1();
  }

  /// @dev Revert reason of the add-side minimum check (LiquidityManagement.addLiquidity).
  function _addSlippageReason() internal pure virtual returns (string memory);

  /// @dev Revert reason of the remove-side minimum check (NonfungiblePositionManager.decreaseLiquidity).
  function _removeSlippageReason() internal pure virtual returns (string memory);

  modifier checkDeadline(uint256 deadline) {
    require(block.timestamp <= deadline, "Transaction too old");
    _;
  }

  /// @dev NonfungiblePositionManager.isAuthorizedForToken.
  modifier isAuthorizedForToken(uint256 tokenId) {
    require(_isAuthorized(_ownerOf(tokenId), msg.sender, tokenId), "Not approved");
    _;
  }

  /// @dev NonfungiblePositionManager.increaseLiquidity: anyone may add; accrued fees move into tokensOwed (they
  ///      are not paid out) before the new liquidity joins the position.
  function increaseLiquidity(INFPM.IncreaseLiquidityParams calldata params)
    external
    payable
    checkDeadline(params.deadline)
    returns (uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    NfpmPosition storage position = _existing(params.tokenId);
    (liquidity, amount0, amount1) = _addLiquidity(
      position.tickLower,
      position.tickUpper,
      params.amount0Desired,
      params.amount1Desired,
      params.amount0Min,
      params.amount1Min
    );
    _syncFees(position, position.liquidity);
    position.liquidity += liquidity;
  }

  /// @dev NonfungiblePositionManager.decreaseLiquidity: owner/approved only, `liquidity > 0`, minimums checked on
  ///      the principal the pool returns, principal plus accrued fees credited to tokensOwed (not paid out).
  function decreaseLiquidity(INFPM.DecreaseLiquidityParams calldata params)
    external
    payable
    isAuthorizedForToken(params.tokenId)
    checkDeadline(params.deadline)
    returns (uint256 amount0, uint256 amount1)
  {
    require(params.liquidity > 0);
    NfpmPosition storage position = _existing(params.tokenId);
    uint128 liquidityBefore = position.liquidity;
    require(liquidityBefore >= params.liquidity);
    (amount0, amount1) = _pool.burn(position.tickLower, position.tickUpper, params.liquidity);
    require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, _removeSlippageReason());
    position.tokensOwed0 += uint128(amount0);
    position.tokensOwed1 += uint128(amount1);
    _syncFees(position, liquidityBefore);
    position.liquidity = liquidityBefore - params.liquidity;
  }

  /// @dev NonfungiblePositionManager.collect: owner/approved only; a live position is poked first
  ///      (`pool.burn(.., 0)`) so pending fee growth joins tokensOwed; pays min(max, owed) of principal plus fees.
  function collect(INFPM.CollectParams calldata params)
    external
    payable
    isAuthorizedForToken(params.tokenId)
    returns (uint256 amount0, uint256 amount1)
  {
    require(params.amount0Max > 0 || params.amount1Max > 0);
    address recipient = params.recipient == address(0) ? address(this) : params.recipient;
    NfpmPosition storage position = _existing(params.tokenId);
    if (position.liquidity > 0) {
      _pool.burn(position.tickLower, position.tickUpper, 0);
      _syncFees(position, position.liquidity);
    }
    uint128 collect0 = params.amount0Max > position.tokensOwed0 ? position.tokensOwed0 : params.amount0Max;
    uint128 collect1 = params.amount1Max > position.tokensOwed1 ? position.tokensOwed1 : params.amount1Max;
    (amount0, amount1) = _pool.collect(recipient, position.tickLower, position.tickUpper, collect0, collect1);
    position.tokensOwed0 -= collect0;
    position.tokensOwed1 -= collect1;
  }

  /// @dev PeripheryPayments.pay from the mint callback: the payer's ERC-20 allowance to this NFPM is spent.
  function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
    require(msg.sender == address(_pool), "callback");
    address payer = abi.decode(data, (address));
    if (amount0Owed > 0) IERC20(_token0).safeTransferFrom(payer, msg.sender, amount0Owed);
    if (amount1Owed > 0) IERC20(_token1).safeTransferFrom(payer, msg.sender, amount1Owed);
  }

  /// @dev Test oracle from this ledger: what `collect(max, max)` would pay right now — tokensOwed plus the fee
  ///      growth a poke would sync (same wrapping mulDiv as `_syncFees`). While no decreased principal is
  ///      waiting in tokensOwed, this is exactly the position's uncollected fees.
  function collectable(uint256 tokenId) external view returns (uint256 amount0, uint256 amount1) {
    NfpmPosition storage position = _positions[tokenId];
    (uint256 inside0, uint256 inside1) = _pool.feeGrowthInside(position.tickLower, position.tickUpper);
    unchecked {
      amount0 = position.tokensOwed0
        + uint128(FullMath.mulDiv(inside0 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128));
      amount1 = position.tokensOwed1
        + uint128(FullMath.mulDiv(inside1 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128));
    }
  }

  function positionLiquidity(uint256 tokenId) external view returns (uint128) {
    return _positions[tokenId].liquidity;
  }

  /// @dev NonfungiblePositionManager.mint core: liquidity is added for this NFPM in the pool and the NFT goes to
  ///      `recipient` with the pool's current fee growth as its snapshot.
  function _mintPosition(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min
  ) internal returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
    (liquidity, amount0, amount1) =
      _addLiquidity(tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min);
    tokenId = nextTokenId++;
    _mint(recipient, tokenId);
    (, uint256 inside0, uint256 inside1,,) = _pool.positions(_positionKey(tickLower, tickUpper));
    _positions[tokenId] = NfpmPosition(tickLower, tickUpper, liquidity, inside0, inside1, 0, 0);
  }

  /// @dev LiquidityManagement.addLiquidity: liquidity from the desired amounts at the current price (rounded down),
  ///      the pool mint charges the rounded-up amounts, and the minimums are checked on what was charged.
  function _addLiquidity(
    int24 tickLower,
    int24 tickUpper,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min
  ) private returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
    liquidity = LiquidityAmounts.getLiquidityForAmounts(
      _pool.sqrtPriceX96(),
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      amount0Desired,
      amount1Desired
    );
    (amount0, amount1) = _pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(msg.sender));
    require(amount0 >= amount0Min && amount1 >= amount1Min, _addSlippageReason());
  }

  /// @dev The NonfungiblePositionManager per-token fee sync: tokensOwed += (feeGrowthInsideLast_pool -
  ///      feeGrowthInsideLast_token) * liquidityBefore / Q128 (wrapping subtraction), then the snapshot moves.
  function _syncFees(NfpmPosition storage position, uint128 liquidityBefore) private {
    (, uint256 inside0, uint256 inside1,,) = _pool.positions(_positionKey(position.tickLower, position.tickUpper));
    unchecked {
      position.tokensOwed0 += uint128(
        FullMath.mulDiv(inside0 - position.feeGrowthInside0LastX128, liquidityBefore, FixedPoint128.Q128)
      );
      position.tokensOwed1 += uint128(
        FullMath.mulDiv(inside1 - position.feeGrowthInside1LastX128, liquidityBefore, FixedPoint128.Q128)
      );
    }
    position.feeGrowthInside0LastX128 = inside0;
    position.feeGrowthInside1LastX128 = inside1;
  }

  function _existing(uint256 tokenId) internal view returns (NfpmPosition storage position) {
    position = _positions[tokenId];
    require(position.tickLower != position.tickUpper, "Invalid token ID");
  }

  /// @dev PositionKey.compute(owner = this NFPM, tickLower, tickUpper).
  function _positionKey(int24 tickLower, int24 tickUpper) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
  }
}

/// @dev Uniswap V3 NonfungiblePositionManager ABI: `positions` reports the fee tier, 'Price slippage check' on
///      both sides.
contract FaithfulUniV3Nfpm is FaithfulNfpmCore {
  uint24 internal immutable _fee;

  constructor(FaithfulUniV3Pool pool_, FaithfulUniV3Factory factory_)
    FaithfulNfpmCore(pool_, address(factory_), "Uniswap V3 Positions NFT-V1")
  {
    _fee = pool_.fee();
  }

  function _addSlippageReason() internal pure override returns (string memory) {
    return "Price slippage check";
  }

  function _removeSlippageReason() internal pure override returns (string memory) {
    return "Price slippage check";
  }

  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    NfpmPosition storage p = _existing(tokenId);
    return (
      0,
      address(0),
      _token0,
      _token1,
      _fee,
      p.tickLower,
      p.tickUpper,
      p.liquidity,
      p.feeGrowthInside0LastX128,
      p.feeGrowthInside1LastX128,
      p.tokensOwed0,
      p.tokensOwed1
    );
  }

  function mint(INFPM.MintParams calldata params)
    external
    payable
    checkDeadline(params.deadline)
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    require(params.token0 == _token0 && params.token1 == _token1 && params.fee == _fee, "pool");
    return _mintPosition(
      params.recipient,
      params.tickLower,
      params.tickUpper,
      params.amount0Desired,
      params.amount1Desired,
      params.amount0Min,
      params.amount1Min
    );
  }
}

/// @dev Slipstream NonfungiblePositionManager ABI: `positions` reports the tick spacing, "PSC" on add
/// (LiquidityManagement) and "PS" on decrease.
contract FaithfulSlipstreamNfpm is FaithfulNfpmCore {
  int24 internal immutable _tickSpacing;

  constructor(FaithfulSlipstreamPool pool_, FaithfulSlipstreamFactory factory_)
    FaithfulNfpmCore(pool_, address(factory_), "Slipstream Position NFT v1")
  {
    _tickSpacing = pool_.tickSpacing();
  }

  function _addSlippageReason() internal pure override returns (string memory) {
    return "PSC";
  }

  function _removeSlippageReason() internal pure override returns (string memory) {
    return "PS";
  }

  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    NfpmPosition storage p = _existing(tokenId);
    return (
      0,
      address(0),
      _token0,
      _token1,
      _tickSpacing,
      p.tickLower,
      p.tickUpper,
      p.liquidity,
      p.feeGrowthInside0LastX128,
      p.feeGrowthInside1LastX128,
      p.tokensOwed0,
      p.tokensOwed1
    );
  }

  /// @dev Slipstream NonfungiblePositionManager.mint keyed by tickSpacing; `sqrtPriceX96` only creates a missing
  ///      pool upstream, and the single pool here always exists, so it must be 0.
  function mint(IAeroNfpm.MintParams calldata params)
    external
    payable
    checkDeadline(params.deadline)
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    require(
      params.token0 == _token0 && params.token1 == _token1 && params.tickSpacing == _tickSpacing
        && params.sqrtPriceX96 == 0,
      "pool"
    );
    return _mintPosition(
      params.recipient,
      params.tickLower,
      params.tickUpper,
      params.amount0Desired,
      params.amount1Desired,
      params.amount0Min,
      params.amount1Min
    );
  }
}
