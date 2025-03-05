// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;
pragma abicoder v2;

import "../libraries/StructHash.sol";

contract StructHashEncoder {
  function encode(StructHash.Order memory order) external pure returns (bytes memory b) {
    b = abi.encode(order);
  }
}
