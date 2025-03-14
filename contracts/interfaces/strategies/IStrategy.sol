// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import { AssetLib } from "../../libraries/AssetLib.sol";

interface IStrategy is ICommon {
  error InvalidAsset();
  error InvalidNumberOfAssets();
  error InvalidInstructionType();

  function valueOf(AssetLib.Asset memory asset, address principalToken) external returns (uint256);

  function convert(AssetLib.Asset[] memory assets, VaultConfig memory config, bytes calldata data)
    external
    returns (AssetLib.Asset[] memory);

  function harvest(AssetLib.Asset memory asset, address tokenOut) external returns (AssetLib.Asset[] memory);

  function getUnderlyingAssets(AssetLib.Asset memory asset) external returns (AssetLib.Asset[] memory);

  function convertFromPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 principalTokenAmount,
    VaultConfig memory config
  ) external returns (AssetLib.Asset[] memory);

  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig memory config
  ) external returns (AssetLib.Asset[] memory);
}
