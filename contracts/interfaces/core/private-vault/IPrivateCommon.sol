// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IPrivateCommon {
  enum CallType {
    DELEGATECALL,
    CALL
  }

  error Unauthorized();

  error ZeroAddress();
}
