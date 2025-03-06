// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ICommon.sol";
import "./IStrategy.sol";

interface IVault is ICommon {
  error InvalidAssetAmount();

  function initialize(
    VaultCreateParams memory params,
    address _owner,
    address _vaultAutomator,
    Asset memory wrapAsset
  ) external;

  function deposit(uint256 amount) external returns (uint256 shares);

  function allocate(Asset[] memory inputAssets, IStrategy strategy, bytes calldata data) external;

  function deallocate(IStrategy strategy, uint256 allocationAmount) external;

  function getTotalValue() external returns (uint256);

  function getAssetAllocations() external returns (Asset[] memory assets, uint256[] memory values);
}
