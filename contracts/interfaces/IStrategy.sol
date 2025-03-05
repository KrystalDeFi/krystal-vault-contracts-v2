// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IStrategy {
  struct DepositDetails {
    address token;
    uint256 tokenId;
    uint256 amount;
  }

  function deposit(uint256 amount, bytes calldata data) external returns (DepositDetails memory);

  function withdraw(uint256 shares) external returns (uint256 amount);

  function getValueInPrinciple(DepositDetails calldata) external returns (uint256 amount);
}
