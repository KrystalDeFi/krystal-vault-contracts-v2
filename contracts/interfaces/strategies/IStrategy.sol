// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import { AssetLib } from "../../libraries/AssetLib.sol";

interface IStrategy is ICommon {
  error InvalidAsset();
  error InvalidNumberOfAssets();
  error InsufficientAmountOut();

  enum FeeType {
    PLATFORM,
    OWNER,
    GAS
  }

  event FeeCollected(FeeType indexed feeType, address indexed recipient, address indexed token, uint256 amount);

  function valueOf(AssetLib.Asset calldata asset, address principalToken) external view returns (uint256);

  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external payable returns (AssetLib.Asset[] memory);

  function harvest(
    AssetLib.Asset calldata asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) external payable returns (AssetLib.Asset[] memory);

  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata config
  ) external payable returns (AssetLib.Asset[] memory);

  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) external payable returns (AssetLib.Asset[] memory);

  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external;
}
