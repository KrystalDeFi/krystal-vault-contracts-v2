// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import { AssetLib } from "./AssetLib.sol";

library InventoryLib {
  error AssetNotFound();

  struct Inventory {
    AssetLib.Asset[] assets;
    mapping(address => mapping(uint256 => uint256)) assetIndex;
  }

  function addAsset(Inventory storage self, AssetLib.Asset memory asset) internal {
    uint256 index = self.assetIndex[asset.token][asset.tokenId];
    if (index == 0) {
      self.assets.push(asset);
      self.assetIndex[asset.token][asset.tokenId] = self.assets.length;
    } else {
      self.assets[index - 1].amount += asset.amount;
    }
  }

  function removeAsset(Inventory storage self, AssetLib.Asset memory asset) internal {
    uint256 index = self.assetIndex[asset.token][asset.tokenId];
    require(index != 0, AssetNotFound());
    AssetLib.Asset storage storedAsset = self.assets[index - 1];
    require(storedAsset.amount >= asset.amount, "InventoryLib: insufficient amount");
    storedAsset.amount -= asset.amount;
  }

  function getAsset(Inventory storage self, address token, uint256 tokenId)
    internal
    view
    returns (AssetLib.Asset memory)
  {
    uint256 index = self.assetIndex[token][tokenId];
    require(index != 0, AssetNotFound());
    return self.assets[index - 1];
  }

  function contains(Inventory storage self, address token, uint256 tokenId) internal view returns (bool) {
    return self.assetIndex[token][tokenId] != 0;
  }
}
