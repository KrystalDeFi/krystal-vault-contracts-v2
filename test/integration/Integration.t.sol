// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, USER } from "../TestCommon.t.sol";

contract IntegrationTest is TestCommon {
  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);
    vm.startBroadcast(USER);
  }

  function test_Integration() public { }
}
