// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

struct PancakeV4PoolKey {
  address currency0;
  address currency1;
  address hooks;
  address poolManager;
  uint24 fee;
  bytes32 parameters;
}

interface ISharedPancakeV4Utils {
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
    address token;
    uint256 amount;
  }

  struct SwapAndMintParams {
    address posm;
    PancakeV4PoolKey poolKey;
    MintParams mintParams;
    SwapParams[] swapParams;
    InputTokenParams[] inputTokens;
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
    uint64 protocolFeeX64;
    uint64 performanceFeeX64;
    uint64 gasFeeX64;
  }

  struct DecreaseAndSwapParams {
    DecreaseLiquidityParams decreaseParams;
    SwapParams[] swapParams;
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

  /// @dev Not `payable`: `SharedPancakeV4Strategy._execute` enforces `ethValue == 0` and
  ///      `_validateVaultToken` rejects `address(0)`, so native-currency pools are not supported.
  function swapAndMint(SwapAndMintParams calldata params) external;

  function swapAndIncrease(SwapAndIncreaseParams calldata params) external;

  function execute(address posm, uint256 tokenId, Instructions calldata instructions) external;
}
