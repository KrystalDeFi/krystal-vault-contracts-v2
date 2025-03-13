// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AssetLib} from "../libraries/AssetLib.sol";

interface ICommon {
  struct VaultCreateParams {
    uint16 ownerFeeBasisPoint;
    string name;
    string symbol;
    address principalToken;
    uint256 principalTokenAmount;
    uint256 principalTokenAmountMin;
    bool allowDeposit;
    address[] supportedTokens;
  }

  struct Instruction {
    uint8 instructionType;
    bytes params;
  }

  error ZeroAddress();

  error TransferFailed();

  error InvalidStrategy();

  error InvalidSwapRouter();
}
