// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICommon {
  struct VaultConfig {
    bool allowDeposit;
    uint8 rangeStrategyType;
    uint8 tvlStrategyType;
    address[] supportedAddresses;
  }

  struct VaultCreateParams {
    uint16 ownerFeeBasisPoint;
    string name;
    string symbol;
    address principalToken;
    uint256 principalTokenAmount;
    VaultConfig config;
  }

  struct Instruction {
    uint8 instructionType;
    bytes params;
  }

  error ZeroAddress();

  error TransferFailed();

  error InvalidVaultConfig();

  error InvalidStrategy();

  error InvalidSwapRouter();
}
