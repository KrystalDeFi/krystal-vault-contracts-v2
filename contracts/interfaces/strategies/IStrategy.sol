// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import { AssetLib } from "../../libraries/AssetLib.sol";

interface IStrategy is ICommon {
  error InvalidAsset();
  error InvalidNumberOfAssets();

  enum FeeType {
    PLATFORM,
    OWNER,
    GAS
  }

  event FeeCollected(FeeType indexed feeType, address indexed recipient, address indexed token, uint256 amount);

  function valueOf(AssetLib.Asset memory asset, address principalToken) external view returns (uint256);

  function convert(
    AssetLib.Asset[] memory assets,
    VaultConfig memory config,
    FeeConfig memory feeConfig,
    bytes calldata data
  ) external returns (AssetLib.Asset[] memory);

  function harvest(AssetLib.Asset memory asset, address tokenOut, FeeConfig memory feeConfig)
    external
    returns (AssetLib.Asset[] memory);

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
    VaultConfig memory config,
    FeeConfig memory feeConfig
  ) external returns (AssetLib.Asset[] memory);

  function revalidate(AssetLib.Asset memory asset, VaultConfig memory config) external;
}
