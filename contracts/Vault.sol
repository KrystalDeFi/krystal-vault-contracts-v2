// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./interfaces/IStrategy.sol";
import "./interfaces/IVault.sol";

contract Vault is IVault {
  address public principalToken;
  mapping(address => mapping(uint256 => Asset)) currentAssets;

  function deposit(uint256 amount) external returns (uint256 shares) {}

  function allocate(Asset[] memory inputAssets, IStrategy strategy, bytes calldata data) external {
    Asset memory currentAsset;
    for (uint256 i = 0; i < inputAssets.length; i++) {
      require(inputAssets[i].amount != 0, InvalidAssetAmount());
      currentAsset = currentAssets[inputAssets[i].token][inputAssets[i].tokenId];
      require(currentAsset.amount >= inputAssets[i].amount, InvalidAssetAmount());
      currentAsset.amount -= inputAssets[i].amount;

      currentAssets[currentAsset.token][currentAsset.tokenId] = currentAsset;
      inputAssets[i].strategy = currentAsset.strategy;
    }

    Asset[] memory newAssets = strategy.convert(inputAssets, data);
    for (uint256 i = 0; i < newAssets.length; i++) {
      currentAsset = currentAssets[newAssets[i].token][newAssets[i].tokenId];
      currentAsset.amount += newAssets[i].amount;

      currentAssets[currentAsset.token][currentAsset.tokenId] = currentAsset;
    }
  }

  function deallocate(IStrategy strategy, uint256 allocationAmount) external {}

  function getTotalValue() external returns (uint256) {}

  function getAssetAllocations() external returns (Asset[] memory assets, uint256[] memory values) {}
}
