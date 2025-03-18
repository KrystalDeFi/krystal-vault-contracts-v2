// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/core/IConfigManager.sol";

/// @title ConfigManager
contract ConfigManager is Ownable, IConfigManager {
  mapping(address => bool) public whitelistStrategies;
  mapping(address => bool) public whitelistSwapRouters;
  mapping(address => bool) public whitelistAutomators;
  // strategy address -> principal token address -> type -> config
  mapping(address => mapping(address => mapping(uint8 => bytes))) public strategyConfigs;

  mapping(address => bool) public stableTokens;
  mapping(address => bool) public peggedTokens;

  uint8 public override maxPositions = 10;

  constructor(
    address _owner,
    address[] memory _stableTokens,
    address[] memory _peggedTokens,
    address[] memory _whitelistAutomator
  ) Ownable(_owner) {
    for (uint256 i = 0; i < _stableTokens.length;) {
      stableTokens[_stableTokens[i]] = true;

      unchecked {
        i++;
      }
    }

    for (uint256 i = 0; i < _peggedTokens.length;) {
      peggedTokens[_peggedTokens[i]] = true;

      unchecked {
        i++;
      }
    }

    for (uint256 i = 0; i < _whitelistAutomator.length;) {
      whitelistAutomators[_whitelistAutomator[i]] = true;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Whitelist strategy
  /// @param _strategies Array of strategy addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistStrategy(address[] memory _strategies, bool _isWhitelisted) external override onlyOwner {
    for (uint256 i = 0; i < _strategies.length;) {
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
    for (uint256 i = 0; i < _swapRouters.length;) {
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

  /// @notice Whitelist automator
  /// @param _automators Array of automator addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistAutomator(address[] memory _automators, bool _isWhitelisted) external override onlyOwner {
    for (uint256 i = 0; i < _automators.length;) {
      whitelistAutomators[_automators[i]] = _isWhitelisted;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Check if automator is whitelisted
  /// @param _automator Automator address
  /// @return _isWhitelisted Boolean value if automator is whitelisted
  function isWhitelistedAutomator(address _automator) external view override returns (bool _isWhitelisted) {
    return whitelistAutomators[_automator];
  }

  /// @notice Set stable tokens
  /// @param _stableTokens Array of stable token addresses
  /// @param _isStable Boolean value to set stable or unstable
  function setStableTokens(address[] memory _stableTokens, bool _isStable) external onlyOwner {
    for (uint256 i = 0; i < _stableTokens.length;) {
      stableTokens[_stableTokens[i]] = _isStable;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Check if token is stable
  /// @param _token Token address
  /// @return _isStable Boolean value if token is stable
  function isStableToken(address _token) external view returns (bool _isStable) {
    return stableTokens[_token];
  }

  /// @notice Set pegged tokens
  /// @param _peggedTokens Array of pegged token addresses
  /// @param _isPegged Boolean value to set pegged or unpegged
  function setPeggedTokens(address[] memory _peggedTokens, bool _isPegged) external onlyOwner {
    for (uint256 i = 0; i < _peggedTokens.length;) {
      peggedTokens[_peggedTokens[i]] = _isPegged;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Check if token is pegged
  /// @param _token Token address
  /// @return _isPegged Boolean value if token is pegged
  function isPeggedToken(address _token) external view returns (bool _isPegged) {
    return peggedTokens[_token];
  }

  /// @notice Get strategy config
  /// @param _strategy Strategy address
  /// @param _type Strategy type
  /// @return _config Strategy config
  function getStrategyConfig(address _strategy, address _principalToken, uint8 _type)
    external
    view
    returns (bytes memory)
  {
    return strategyConfigs[_strategy][_principalToken][_type];
  }

  /// @notice Set strategy config
  /// @param _strategy Strategy address
  /// @param _type Strategy type
  /// @param _config Strategy config
  function setStrategyConfig(address _strategy, address _principalToken, uint8 _type, bytes memory _config)
    external
    onlyOwner
  {
    strategyConfigs[_strategy][_principalToken][_type] = _config;
  }

  /// @notice Set max positions
  /// @param _maxPositions Max positions
  function setMaxPositions(uint8 _maxPositions) external onlyOwner {
    maxPositions = _maxPositions;
  }
}
