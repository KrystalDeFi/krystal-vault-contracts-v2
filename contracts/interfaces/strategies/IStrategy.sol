// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IStrategy is ICommon {
  error InvalidAsset();
  error InvalidNumberOfAssets();
  error InvalidInstructionType();

  function valueOf(Asset memory asset) external returns (Asset[] memory assets);

  function convert(Asset[] memory assets, bytes calldata data) external returns (Asset[] memory);

  function harvest(Asset memory asset) external returns (Asset[] memory);

  function getUnderlyingAssets(Asset memory asset) external returns (Asset[] memory);

  function convertIntoExisting(Asset memory existingAsset, Asset[] memory assets) external returns (Asset[] memory);
}
