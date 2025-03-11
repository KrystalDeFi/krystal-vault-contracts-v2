// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Common is Test {
  using stdStorage for StdStorage;

  function setErc20Balance(address token, address account, uint256 amount) internal {
    stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(account).checked_write(amount);
  }
}
