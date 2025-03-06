// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICommon {
  struct Asset {
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
    Asset[] assets;
  }

  error ZeroAddress();

  error TransferFailed();
}
