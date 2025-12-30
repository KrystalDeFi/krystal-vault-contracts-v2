// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBGT is IERC20 {
  function redeem(address receiver, uint256 amount) external;
}
