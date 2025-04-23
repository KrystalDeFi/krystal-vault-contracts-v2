// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IFeeTaker {
  enum FeeType {
    PLATFORM,
    OWNER,
    GAS
  }

  event FeeCollected(address indexed vaultAddress, FeeType indexed feeType, address indexed recipient, address token, uint256 amount);
}
