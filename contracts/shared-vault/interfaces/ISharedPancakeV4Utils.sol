// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";

interface ISharedPancakeV4Utils {
  // Action events — byte-compatible with v4utils `IV4Utils` (pancakev4) so existing decoders work
  // unchanged. Emitted by SharedPancakeV4StrategyLib / SharedV4SwapPipeline under delegatecall
  // from SharedVault, so the logs surface at the vault address.
  event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
  event SwapAndMint(address indexed posm, uint256 indexed tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);
  event SwapAndIncrease(
    address indexed posm, uint256 indexed tokenId, uint256 liquidity, uint256 amount0, uint256 amount1
  );
  /// @dev `token`/`amount` report `swapDestToken` and this operation's post-swap proceeds in it
  ///      (0 when `swapDestToken` is not a pool token). Unlike v4utils nothing is swept — the
  ///      proceeds stay idle in the vault.
  event DecreaseAndSwap(
    address indexed posm, uint256 indexed tokenId, uint128 liquidity, Currency token, uint256 amount
  );
  event AdjustRange(
    address indexed posm,
    uint256 indexed tokenId,
    uint256 newTokenId,
    uint256 newLiquidity,
    uint256 token0Added,
    uint256 token1Added
  );
  event CompoundFees(
    address indexed posm, uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1
  );

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

  /// @dev SharedV4SwapPipeline forwards `amountIn` to signature verification verbatim — the digest
  ///      binds this exact amount, never an on-chain computed balance — and the tracked total only
  ///      needs to cover it (the backend folds withdraw-liquidity slippage into the signed amount;
  ///      the un-swapped remainder stays in the totals). `amountIn == 0` means "no swap for this hop"
  ///      (`amountOutMin` must be 0); it is NOT resolved to the available balance. `amountOutMin` is
  ///      signer-controlled; signers must apply their own route/oracle slippage policy.
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
  // SharedPancakeV4StrategyLib never reads them; performance fees come exclusively from
  // `performanceFeeConfig()`.
  // ABI compatibility note: `sweepTokens` and `swapDestToken` mirror legacy V4Utils payload
  // shapes. `sweepTokens` is never read. `swapDestToken` is read ONLY to label the
  // `DecreaseAndSwap` event (no transfer semantics). Neither triggers on-chain sweeping or
  // selects a swap destination in the shared strategy; pool-token balances remain idle in
  // the vault, and non-pool intermediates must net to zero through SharedV4SwapPipeline.

  struct SwapAndMintParams {
    address posm;
    PoolKey poolKey;
    MintParams mintParams;
    SwapParams[] swapParams;
    InputTokenParams[] inputTokens;
    // Unread by SharedPancakeV4StrategyLib; retained only for ABI-compatible V4Utils payloads.
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
    // Unread by SharedPancakeV4StrategyLib; retained only for ABI-compatible V4Utils payloads.
    Currency[] sweepTokens;
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  struct DecreaseAndSwapParams {
    DecreaseLiquidityParams decreaseParams;
    SwapParams[] swapParams;
    // Read only to label the DecreaseAndSwap event; no transfer/sweep semantics.
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
