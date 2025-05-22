// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IWETH9 } from "../../interfaces/IWETH9.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BgtRedeemer {
  IWETH9 private wbera;
  address private receiver;

  constructor(address _wbera) {
    wbera = IWETH9(_wbera);
  }

  function setReceiver(address _receiver) external {
    receiver = _receiver;
  }

  receive() external payable {
    IWETH9(wbera).deposit{ value: msg.value }();
    IERC20(wbera).transfer(receiver, msg.value);
  }
}
