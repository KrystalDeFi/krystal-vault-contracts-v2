// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import { AssetLib } from "./AssetLib.sol";

library InventoryLib {
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
    require(index != 0, "InventoryLib: asset not found");
    AssetLib.Asset storage storedAsset = self.assets[index - 1];
    require(storedAsset.amount >= asset.amount, "InventoryLib: insufficient amount");
    if (storedAsset.amount == asset.amount) {
      if (index < self.assets.length) {
        AssetLib.Asset storage lastAsset = self.assets[self.assets.length - 1];
        self.assets[index - 1] = lastAsset;
        self.assetIndex[lastAsset.token][lastAsset.tokenId] = index;
      }
      self.assets.pop();
      delete self.assetIndex[asset.token][asset.tokenId];
    } else {
      storedAsset.amount -= asset.amount;
    }
  }

  function getAsset(Inventory storage self, address token, uint256 tokenId) internal view returns (AssetLib.Asset memory) {
    uint256 index = self.assetIndex[token][tokenId];
    require(index != 0, "InventoryLib: asset not found");
    return self.assets[index - 1];
  }

  function contains(Inventory storage self, address token, uint256 tokenId) internal view returns (bool) {
    return self.assetIndex[token][tokenId] != 0;
  }
}
