// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IWhitelistManager.sol";

/// @title WhitelistManager
contract WhitelistManager is Ownable, IWhitelistManager {
  mapping(address => bool) public whitelistStrategies;

  constructor() Ownable(_msgSender()) {}

  /// @notice Whitelist strategy
  /// @param _strategies Array of strategy addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistStrategy(address[] memory _strategies, bool _isWhitelisted) external override onlyOwner {
    for (uint256 i = 0; i < _strategies.length; ) {
      whitelistStrategies[_strategies[i]] = _isWhitelisted;

      unchecked {
        i++;
      }
    }
  }

  function isWhitelisted(address _strategy) external view override returns (bool _isWhitelisted) {
    return whitelistStrategies[_strategy];
  }
}
