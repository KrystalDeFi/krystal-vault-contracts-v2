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
    if (asset.amount == 0) return;
    uint256 index = self.assetIndex[asset.token][asset.tokenId];
    if (index == 0) {
      self.assets.push(asset);
      self.assetIndex[asset.token][asset.tokenId] = self.assets.length;
    } else {
      self.assets[index - 1].amount += asset.amount;
    }
  }

  function removeAsset(Inventory storage self, AssetLib.Asset memory asset) internal {
    removeAsset(self, asset, false);
  }

  function removeAsset(Inventory storage self, AssetLib.Asset memory asset, bool _delete) internal {
    uint256 index = self.assetIndex[asset.token][asset.tokenId] - 1;
    AssetLib.Asset storage storedAsset = self.assets[index];
    require(storedAsset.amount >= asset.amount, "InventoryLib: insufficient amount");
    storedAsset.amount -= asset.amount;
    if (!_delete) return;
    if (storedAsset.amount == 0) {
      delete self.assetIndex[storedAsset.token][storedAsset.tokenId];

      if (index != self.assets.length - 1) {
        AssetLib.Asset storage lastAsset = self.assets[self.assets.length - 1];
        self.assetIndex[lastAsset.token][lastAsset.tokenId] = index + 1;

        self.assets[index] = lastAsset;
      }
      self.assets.pop();
    }
  }

  function removeAsset(Inventory storage self, uint256 index) internal {
    AssetLib.Asset storage storedAsset = self.assets[index];
    delete self.assetIndex[storedAsset.token][storedAsset.tokenId];

    if (index != self.assets.length - 1) {
      AssetLib.Asset storage lastAsset = self.assets[self.assets.length - 1];
      self.assetIndex[lastAsset.token][lastAsset.tokenId] = index + 1;

      self.assets[index] = lastAsset;
    }
    self.assets.pop();
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
