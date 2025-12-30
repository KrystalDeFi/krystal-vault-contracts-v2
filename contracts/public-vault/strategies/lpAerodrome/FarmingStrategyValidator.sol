// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../../common/interfaces/protocols/aerodrome/ICLGauge.sol";
import "../../interfaces/strategies/aerodrome/IFarmingStrategyValidator.sol";

/**
 * @title FarmingStrategyValidator
 * @notice Validates ICLGauge addresses against whitelisted factories
 * @dev Prevents malicious gauge attacks by ensuring gauges belong to trusted factories
 */
contract FarmingStrategyValidator is IFarmingStrategyValidator, Ownable {
  // Storage
  mapping(address => bool) public whitelistedFactories;
  address[] private factoryList;

  /**
   * @notice Constructor
   * @param initialOwner Address of the initial owner
   * @param initialFactories Array of initial factory addresses to whitelist
   */
  constructor(address initialOwner, address[] memory initialFactories) Ownable(initialOwner) {
    require(initialOwner != address(0), ZeroAddress());

    for (uint256 i = 0; i < initialFactories.length; i++) {
      _addFactory(initialFactories[i]);
    }
  }

  /**
   * @notice Validate that a gauge address is safe to use
   * @param gauge Address of the ICLGauge to validate
   * @dev Reverts if gauge is invalid or belongs to non-whitelisted factory
   */
  function validateGauge(address gauge) external view override {
    require(whitelistedFactories[ICLGauge(gauge).gaugeFactory()], InvalidFactory());
  }

  /**
   * @notice Check if a gauge address is valid without reverting
   * @param gauge Address of the ICLGauge to check
   * @return valid True if gauge is valid, false otherwise
   */
  function isValidGauge(address gauge) external view override returns (bool valid) {
    if (gauge == address(0)) return false;

    try ICLGauge(gauge).gaugeFactory() returns (address factory) {
      return whitelistedFactories[factory];
    } catch {
      return false;
    }
  }

  /**
   * @notice Check if a factory is whitelisted
   * @param factory Address of the ICLFactory to check
   * @return whitelisted True if factory is whitelisted, false otherwise
   */
  function isWhitelistedFactory(address factory) external view override returns (bool whitelisted) {
    return whitelistedFactories[factory];
  }

  /**
   * @notice Add a factory to the whitelist
   * @param factory Address of the ICLFactory to whitelist
   * @dev Only callable by owner
   */
  function addFactory(address factory) external override onlyOwner {
    _addFactory(factory);
  }

  /**
   * @notice Remove a factory from the whitelist
   * @param factory Address of the ICLFactory to remove
   * @dev Only callable by owner
   */
  function removeFactory(address factory) external override onlyOwner {
    require(factory != address(0), ZeroAddress());
    require(whitelistedFactories[factory], FactoryNotFound());

    whitelistedFactories[factory] = false;

    // Remove from factoryList array
    for (uint256 i = 0; i < factoryList.length; i++) {
      if (factoryList[i] == factory) {
        factoryList[i] = factoryList[factoryList.length - 1];
        factoryList.pop();
        break;
      }
    }

    emit FactoryRemoved(factory);
  }

  /**
   * @notice Get all whitelisted factories
   * @return factories Array of whitelisted factory addresses
   */
  function getWhitelistedFactories() external view override returns (address[] memory factories) {
    return factoryList;
  }

  /**
   * @notice Internal function to add a factory to the whitelist
   * @param factory Address of the ICLFactory to whitelist
   */
  function _addFactory(address factory) internal {
    require(factory != address(0), ZeroAddress());
    require(!whitelistedFactories[factory], FactoryAlreadyAdded());

    whitelistedFactories[factory] = true;
    factoryList.push(factory);

    emit FactoryAdded(factory);
  }
}
