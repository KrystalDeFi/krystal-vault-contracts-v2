// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./interfaces/IStrategy.sol";

contract LpStrategy is IStrategy {
  address public router;
  struct DepositParams {
    uint256 tokenId;
  }

  function deposit(uint256 amount, bytes calldata data) external override returns (DepositDetails memory details) {
  }

  function getValueInPrinciple(DepositDetails memory details) external override returns (uint256) {
    return details.amount;
  }

  function withdraw(uint256 amount) external returns (uint256) {
  }

  function compound(uint256 value) external returns (uint256) {
  }
}
