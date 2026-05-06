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
  ///                            INVARIANT: action.target is stored as pos.strategy for any positions added via this
  ///                            path. During withdraw(), exitProportional is always delegatecalled on pos.strategy
  ///                            regardless of how the position was originally created. The target must therefore be a
  ///                            fully-trusted ISharedStrategy implementation — the same requirement as DELEGATECALL.
  ///                            Unlike CALL, no token pre-approval or post-call balance validation is performed;
  ///                            callers must ensure the target only executes authorised LP operations.
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
  error TransferFailed();
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
  /// @notice NFPM must implement `IERC721Enumerable` (`tokenOfOwnerByIndex`) to locate the new token after `CHANGE_RANGE`.
  error NfpmEnumerableRequired();
  error InvalidNfpm(address nfpm);
  error InvalidSwapRouter(address swapRouter);
  error TooManyPositions();
}
