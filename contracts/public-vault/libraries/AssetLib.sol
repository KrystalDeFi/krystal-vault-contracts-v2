// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

library AssetLib {
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
}
