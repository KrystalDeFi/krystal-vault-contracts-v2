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

  /// @dev `amountIn == 0` means "use the full available amount" in SharedV4SwapPipeline. For signed
  ///      operator swaps, the signature binds the resolved runtime amount, not this zero sentinel.
  ///      `amountOutMin` is signer-controlled; signers must apply their own route/oracle slippage policy.
  struct SwapParams {
    Currency tokenIn;
    uint256 amountIn;
    Currency tokenOut;
    uint256 amountOutMin;
    bytes swapData;
  }

  struct InputTokenParams {
    Currency token;
    uint256 amount;
  }

  // Fee model: platform/owner (performance) fees are always sourced from
  // `SharedStrategyFeeConfig.performanceFeeConfig()`. Only `gasFeeX64` is honored on these structs,
  // subject to `configManager.maxGasFeeX64()` (skimmed to the configured fee recipient).
  // The legacy `protocolFeeX64`/`performanceFeeX64` fields (and `AdjustRangeParams.compoundFees`)
  // are retained ONLY for backward-compatible ABI encoding with existing off-chain callers —
  // SharedV4StrategyLib never reads them; performance fees come exclusively from
  // `performanceFeeConfig()`.
  // ABI compatibility note: `sweepTokens` and `swapDestToken` mirror legacy V4Utils payload
  // shapes but SharedV4StrategyLib does NOT read them. They do not trigger on-chain sweeping
  // or select a swap destination in the shared strategy; pool-token balances remain idle in
  // the vault, and non-pool intermediates must net to zero through SharedV4SwapPipeline.

  struct SwapAndMintParams {
    address posm;
    PoolKey poolKey;
    MintParams mintParams;
    SwapParams[] swapParams;
    InputTokenParams[] inputTokens;
    // Unread by SharedV4StrategyLib; retained only for ABI-compatible V4Utils payloads.
    Currency[] sweepTokens;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  struct SwapAndIncreaseParams {
    address posm;
    uint256 tokenId;
    IncreaseLiquidityParams increaseParams;
    SwapParams[] swapParams;
    InputTokenParams[] inputTokens;
    // Unread by SharedV4StrategyLib; retained only for ABI-compatible V4Utils payloads.
    Currency[] sweepTokens;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  struct DecreaseAndSwapParams {
    DecreaseLiquidityParams decreaseParams;
    SwapParams[] swapParams;
    // Unread by SharedV4StrategyLib; retained only for ABI-compatible V4Utils payloads.
    Currency swapDestToken;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  struct AdjustRangeParams {
    bytes collectFeesHookData;
    SwapParams[] swapParams;
    MintParams mintParams;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
    // Unread (see fee-model note above); retained for backward-compatible ABI encoding. The
    // old position's full-liquidity burn is no longer bounded by a separate decrease floor —
    // the rebalance round-trip is validated by `mintParams.minLiquidity` on the re-mint.
    bool compoundFees;
  }

  struct CompoundFeesParams {
    bytes collectFeesHookData;
    SwapParams[] swapParams;
    IncreaseLiquidityParams increaseParams;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  function swapAndMint(SwapAndMintParams calldata params) external payable;

  function swapAndIncrease(SwapAndIncreaseParams calldata params) external;

  function execute(address posm, uint256 tokenId, Instructions calldata instructions) external;
}
