// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/IStrategy.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract LpStrategyImpl is Initializable, ReentrancyGuardUpgradeable, IStrategy {
  address public principalToken;

  constructor() {}

  function initialize(address _principalToken) public initializer {
    __ReentrancyGuard_init();

    principalToken = _principalToken;
  }

  /// @notice Deposits the asset to the strategy
  function valueOf(Asset memory asset) external view returns (uint256 value) {
    INFPM(asset.token).positions(asset.tokenId);
  }

  /// @notice Converts the asset to another assets
  function convert(Asset[] memory assets, bytes calldata data) external returns (Asset[] memory) {}

  function convertIntoExisting(
    Asset memory existingAsset,
    Asset[] memory newAssets,
    bytes calldata data
  ) external returns (Asset[] memory asset) {}

  receive() external payable {}
}
