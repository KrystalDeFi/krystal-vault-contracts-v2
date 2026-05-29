// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface ISharedV4Utils {
  enum UtilActions {
    ADJUST_RANGE,
    DECREASE_AND_SWAP,
    COMPOUND
  }

  struct Instructions {
    UtilActions action;
    bytes params;
  }

  struct DecreaseLiquidityParams {
    uint128 liquidity;
    uint256 deadline;
    uint256 amount0Min;
    uint256 amount1Min;
    bytes hookData;
  }

  struct MintParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 minLiquidity;
    bytes hookData;
    uint256 deadline;
  }

  struct IncreaseLiquidityParams {
    uint256 minLiquidity;
    bytes hookData;
    uint256 deadline;
  }

  struct SwapParams {
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
    uint256 amountOutMin;
    bytes swapData;
  }

  struct InputTokenParams {
    Currency token;
    uint256 amount;
  }

  // Fee model: platform/owner (performance) fees are always sourced from
  // `SharedStrategyFeeConfig.performanceFeeConfig()`. Only `gasFeeX64` is honored on these structs
  // (skimmed to `msg.sender`/the authorized executor). The legacy `protocolFeeX64`/`performanceFeeX64`
  // V4Utils fields were never read by SharedV4StrategyLib and have been removed.

  struct SwapAndMintParams {
    address posm;
    PoolKey poolKey;
    MintParams mintParams;
    SwapParams[] swapParams;
    InputTokenParams[] inputTokens;
    uint64 gasFeeX64;
  }

  struct SwapAndIncreaseParams {
    address posm;
    uint256 tokenId;
    IncreaseLiquidityParams increaseParams;
    SwapParams[] swapParams;
    InputTokenParams[] inputTokens;
    uint64 gasFeeX64;
  }

  struct DecreaseAndSwapParams {
    DecreaseLiquidityParams decreaseParams;
    SwapParams[] swapParams;
    uint64 gasFeeX64;
  }

  struct AdjustRangeParams {
    bytes collectFeesHookData;
    SwapParams[] swapParams;
    MintParams mintParams;
    uint64 gasFeeX64;
    // Minimum token amounts to receive from burning the OLD position's full liquidity. Set these to
    // an off-chain-fair value (not 0) to bound the decrease against sandwich/price manipulation;
    // they mirror DECREASE_AND_SWAP's amount0Min/amount1Min. 0 disables the floor on the burn.
    uint256 decreaseAmount0Min;
    uint256 decreaseAmount1Min;
  }

  struct CompoundFeesParams {
    bytes collectFeesHookData;
    SwapParams[] swapParams;
    IncreaseLiquidityParams increaseParams;
    uint64 gasFeeX64;
  }

  function swapAndMint(SwapAndMintParams calldata params) external;

  function swapAndIncrease(SwapAndIncreaseParams calldata params) external;

  function execute(address posm, uint256 tokenId, Instructions calldata instructions) external;
}
