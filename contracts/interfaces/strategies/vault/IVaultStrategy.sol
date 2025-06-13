// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../IStrategy.sol";

interface IVaultStrategy is IStrategy {
  error PrincipalTokenMismatch();
  error InvalidVault();

  enum InstructionType {
    Deposit,
    Withdraw
  }

  struct DepositParams {
    address vault;
    uint256 principalAmount;
    uint256 minShares;
  }

  struct WithdrawParams {
    uint256 shares;
    bool unwrap;
    uint256 minReturnAmount;
  }
}
