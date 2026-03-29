// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedCommon {
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
}
