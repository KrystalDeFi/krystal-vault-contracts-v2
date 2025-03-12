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
    uint16 ownerFeeBasisPoint;
    string name;
    string symbol;
    address principalToken;
    uint256 principalTokenAmount;
  }

  struct Instruction {
    uint8 instructionType;
    bytes params;
  }

  error ZeroAddress();

  error TransferFailed();

  error InvalidStrategy();
}
