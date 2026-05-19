// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract TestHelper {
  uint256 public value;
  constructor() {
    value = 42;
  }
}

contract TestDeployContracts {
  uint256 public immutable helperValue;

  constructor() {
    // Read from the pre-deployed TestHelper at a known address
    helperValue = TestHelper(0x00000000000000000000000000000000De010662).value();
  }

  function verify() external pure {
    assert(false);
  }
}
