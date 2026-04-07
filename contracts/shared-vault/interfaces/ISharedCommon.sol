// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedCommon {
  /// @notice Call discipline for vault execution.
  ///   DELEGATECALL           — delegatecall target as a whitelisted strategy implementing ISharedStrategy.execute().
  ///                            Result is always PositionChange[]: non-empty for LP adds/removes, empty for token-only
  ///                            operations (e.g., harvest, rebalance-swap) where only vault token balances change.
  ///   CALL                   — direct call to a swap aggregator.
  ///                            action.data must be abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata).
  ///                            tokenIn/tokenOut must be vault tokens; output balance delta is checked against minAmountOut.
  ///   CALL_WITH_POSITIONS    — direct call to a target that returns PositionChange[].
  ///                            action.data is the raw calldata forwarded to the target.
  ///                            The result is decoded as PositionChange[] and LP positions are tracked accordingly.
  enum CallType {
    DELEGATECALL,
    CALL,
    CALL_WITH_POSITIONS
  }

  error Unauthorized();
  error ZeroAddress();
  error InvalidAmount();
  error InvalidToken();
  error InvalidRatio();
  error VaultPaused();
  error InvalidTarget(address target);
  error InvalidStrategy(address strategy);
  error StrategyCallFailed();
  error SwapFailed();
  error InsufficientShares();
  error InsufficientOutput();
  error NoTokensConfigured();
  error DuplicateToken();
  error TokenNotConfigured();
  error CannotSweepVaultToken();
  error InvalidOperation();
  error LengthMismatch();
  error InvalidVaultOwnerFeeBasisPoint();
  error InvalidFeeBasisPoint();
}
