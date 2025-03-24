// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICommon {
  struct VaultConfig {
    bool allowDeposit;
    uint8 rangeStrategyType;
    uint8 tvlStrategyType;
    address principalToken;
    address[] supportedAddresses;
  }

  struct VaultCreateParams {
    uint16 ownerFeeBasisPoint;
    string name;
    string symbol;
    uint256 principalTokenAmount;
    VaultConfig config;
  }

  struct FeeConfig {
    uint16 vaultOwnerFeeBasisPoint;
    address vaultOwner;
    uint16 platformFeeBasisPoint;
    address platformFeeRecipient;
    uint16 gasFeeBasisPoint;
    address gasFeeRecipient;
  }

  struct Instruction {
    uint8 instructionType;
    bytes params;
  }

  error ZeroAddress();

  error TransferFailed();

  error InvalidVaultConfig();

  error InvalidFeeConfig();

  error InvalidStrategy();

  error InvalidSwapRouter();

  error InvalidInstructionType();
}
