// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/**
 * @title IFarmingStrategyValidator
 * @notice Interface for validating ICLGauge addresses in FarmingStrategy
 * @dev Validates that gauges belong to whitelisted factories to prevent malicious gauge attacks
 */
interface IFarmingStrategyValidator {
  // Events
  event FactoryAdded(address indexed factory);
  event FactoryRemoved(address indexed factory);

  // Errors
  error ZeroAddress();
  error InvalidFactory();
  error InvalidGauge();
  error FactoryAlreadyAdded();
  error FactoryNotFound();

  /**
   * @notice Validate that a gauge address is safe to use
   * @param gauge Address of the ICLGauge to validate
   * @dev Reverts if gauge is invalid or belongs to non-whitelisted factory
   */
  function validateGauge(address gauge) external view;

  /**
   * @notice Check if a gauge address is valid without reverting
   * @param gauge Address of the ICLGauge to check
   * @return valid True if gauge is valid, false otherwise
   */
  function isValidGauge(address gauge) external view returns (bool valid);

  /**
   * @notice Check if a factory is whitelisted
   * @param factory Address of the ICLFactory to check
   * @return whitelisted True if factory is whitelisted, false otherwise
   */
  function isWhitelistedFactory(address factory) external view returns (bool whitelisted);

  /**
   * @notice Add a factory to the whitelist
   * @param factory Address of the ICLFactory to whitelist
   * @dev Only callable by authorized admin
   */
  function addFactory(address factory) external;

  /**
   * @notice Remove a factory from the whitelist
   * @param factory Address of the ICLFactory to remove
   * @dev Only callable by authorized admin
   */
  function removeFactory(address factory) external;

  /**
   * @notice Get all whitelisted factories
   * @return factories Array of whitelisted factory addresses
   */
  function getWhitelistedFactories() external view returns (address[] memory factories);
}
