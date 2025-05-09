// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "../../interfaces/strategies/IStrategy.sol";
import { AssetLib } from "../../libraries/AssetLib.sol";

contract LpMigrator is IStrategy {
  address public immutable oldStrategy;
  address public immutable newStrategy;

  constructor(address _oldStrategy, address _newStrategy) {
    oldStrategy = _oldStrategy;
    newStrategy = _newStrategy;
  }

  function valueOf(AssetLib.Asset calldata asset, address principalToken) external view returns (uint256) {
    return 0;
  }

  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external payable returns (AssetLib.Asset[] memory result) {
    uint256 length = assets.length;
    result = new AssetLib.Asset[](length);
    for (uint256 i = 0; i < length; i++) {
      AssetLib.Asset memory asset = assets[i];
      require(asset.strategy == oldStrategy, InvalidStrategy());
      asset.strategy = newStrategy;
      result[i] = asset;
    }
  }

  function harvest(
    AssetLib.Asset calldata asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) external payable returns (AssetLib.Asset[] memory) { }

  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata config
  ) external payable returns (AssetLib.Asset[] memory) { }

  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) external payable returns (AssetLib.Asset[] memory) { }

  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external { }
}
