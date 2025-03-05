// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./interfaces/IStrategy.sol";

contract Vault {
  mapping(address => IStrategy.DepositDetails) public stratsAlloc;
  IStrategy[] public strategies;

  function deposit(uint256 amount) external returns (uint256 shares) {
  }

  function allocate(uint256 amount, IStrategy strategy, bytes calldata data) external {
    strategies.push(strategy);
    stratsAlloc[address(strategy)] = strategy.deposit(amount, data);
  }

  function deallocate(IStrategy strategy, uint256 allocationAmount) external {
  }

  function getTotalValue() external returns (uint256) {
    uint256 totalValue = 0;
    for (uint256 i = 0; i < strategies.length; i++) {
      IStrategy strategy = strategies[i];
      totalValue += strategy.getValueInPrinciple(stratsAlloc[address(strategy)]);
    }
    return totalValue;
  }
}
