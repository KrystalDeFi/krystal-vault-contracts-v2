// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICommon {
  enum AssetType {
    ERC20,
    ERC721,
    ERC1155
  }
  struct Asset {
    AssetType assetType;
    address strategy;
    address token;
    uint256 tokenId;
    uint256 amount;
  }

  struct VaultCreateParams {
    // [REVIEW]: to be updated one we finalize the fee structure.
    uint16 ownerFeeBasisPoint;
    string name;
    string symbol;
    // [TODO]: typo: principal => principle
    address principalToken;
    uint256 principalTokenAmount;
  }

  struct Instruction {
    uint8 instructionType;
    bytes params;
    bytes abiEncodedUserOrder;
    bytes orderSignature;
  }

  error ZeroAddress();

  error TransferFailed();

  error InvalidStrategy();
}
