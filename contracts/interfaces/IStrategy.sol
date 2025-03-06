// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ICommon.sol";

interface IStrategy {
  function valueOf(Asset memory asset) external returns (uint256 value);

  /// @notice Converts the asset to another assets
  function convert(Asset[] memory assets, bytes calldata data) external returns (Asset[] memory);
  
  function convertIntoExisting(Asset memory existingAsset, Asset[] memory newAssets, bytes calldata data) external returns (Asset[] memory asset);
}
