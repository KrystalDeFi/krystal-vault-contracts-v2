// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/core/IWhitelistManager.sol";

/// @title WhitelistManager
contract WhitelistManager is Ownable, IWhitelistManager {
  mapping(address => bool) public whitelistStrategies;
  mapping(address => bool) public whitelistSwapRouters;

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

  /// @notice Check if strategy is whitelisted
  /// @param _strategy Strategy address
  /// @return _isWhitelisted Boolean value if strategy is whitelisted
  function isWhitelistedStrategy(address _strategy) external view override returns (bool _isWhitelisted) {
    return whitelistStrategies[_strategy];
  }

  /// @notice Whitelist swap router
  /// @param _swapRouters Array of swap router addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistSwapRouter(address[] memory _swapRouters, bool _isWhitelisted) external override onlyOwner {
    for (uint256 i = 0; i < _swapRouters.length; ) {
      whitelistSwapRouters[_swapRouters[i]] = _isWhitelisted;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Check if swap router is whitelisted
  /// @param _swapRouter Swap router address
  /// @return _isWhitelisted Boolean value if swap router is whitelisted
  function isWhitelistedSwapRouter(address _swapRouter) external view override returns (bool _isWhitelisted) {
    return whitelistSwapRouters[_swapRouter];
  }
}
