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
    string name;
    string symbol;
    uint256 principalTokenAmount;
    uint16 vaultOwnerFeeBasisPoint;
    VaultConfig config;
  }

  struct FeeConfig {
    uint16 vaultOwnerFeeBasisPoint;
    address vaultOwner;
    uint16 platformFeeBasisPoint;
    address platformFeeRecipient;
    uint64 gasFeeX64;
    address gasFeeRecipient;
  }

  struct Instruction {
    uint8 instructionType;
    bytes params;
  }

  error ZeroAddress();

  error TransferFailed();

  error ExternalCallFailed();

  error InvalidVaultConfig();

  error InvalidFeeConfig();

  error InvalidStrategy();

  error InvalidSwapRouter();

  error InvalidInstructionType();

  error InvalidSigner();

  error SignatureExpired();

  error ApproveFailed();

  error InvalidParams();
}
