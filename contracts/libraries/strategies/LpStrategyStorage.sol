// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IOptimalSwapper } from "../../interfaces/core/IOptimalSwapper.sol";
import { ILpValidator } from "../../interfaces/strategies/ILpValidator.sol";
import "forge-std/console.sol";

library LpStrategyStorage {
  bytes32 constant POSITION_SLOT = keccak256("LpStrategyStorage");

  struct Storage {
    IOptimalSwapper optimalSwapper;
    ILpValidator validator;
  }

  function getStorage() external view returns (Storage storage s) {
    bytes32 sl = POSITION_SLOT;
    console.log("POSITION_SLOT");
    console.logBytes32(sl);
    assembly {
      s.slot := sl
    }
    console.log("optimalSwapper", address(s.optimalSwapper));
    console.log("validator", address(s.validator));
  }
}
