// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "../interfaces/core/IConfigManager.sol";

/// @title ConfigManager
contract ConfigManager is Ownable, IConfigManager {
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  mapping(address => bool) public whitelistStrategies;
  mapping(address => bool) public whitelistSwapRouters;
  mapping(address => bool) public whitelistAutomators;

  // strategy address -> principal token address -> encoded config
  /* 
    E.g.: LpStrategy -> WETH -> encoded config
    address(LpStrategy): {
      address(WETH): abi.encode({
        // Multiple by tick spacing
        rangeConfigs: [
          // Narrow
          {
            tickWidthMultiplierMin: 20,
            tickWidthStableMultiplierMin: 10
          },
          // Wide
          {
            tickWidthMultiplierMin: 10,
            tickWidthStableMultiplierMin: 5
          }
        ],
        // Min by token amount
        tvlConfigs: [
          // Low
          {
            principalTokenAmountMin: 100,
          },
          // High
          {
            principalTokenAmountMin: 1000000,
          }
        ],
      });
    }
  */
  mapping(address => mapping(address => bytes)) public strategyConfigs;

  // 0 = stable token
  // 1 = pegged token
  // ...
  EnumerableMap.AddressToUintMap private typedTokens;

  uint8 public override maxPositions = 10;

  constructor(
    address _owner,
    address[] memory _whitelistAutomator,
    address[] memory _typedTokens,
    uint256[] memory _typedTokenTypes
  ) Ownable(_owner) {
    for (uint256 i = 0; i < _typedTokens.length;) {
      typedTokens.set(_typedTokens[i], _typedTokenTypes[i]);

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

  /// @notice Get typed tokens
  /// @return _typedTokens Typed tokens
  /// @return _typedTokenTypes Typed token types
  function getTypedTokens()
    external
    view
    override
    returns (address[] memory _typedTokens, uint256[] memory _typedTokenTypes)
  {
    uint256 length = typedTokens.length();
    _typedTokens = new address[](length);
    _typedTokenTypes = new uint256[](length);

    for (uint256 i = 0; i < length;) {
      (address key, uint256 value) = typedTokens.at(i);
      _typedTokens[i] = key;
      _typedTokenTypes[i] = value;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Set typed tokens
  /// @param _typedTokens Array of typed token addresses
  /// @param _typedTokenTypes Array of typed token types
  function setTypedTokens(address[] memory _typedTokens, uint256[] memory _typedTokenTypes) external onlyOwner {
    for (uint256 i = 0; i < _typedTokens.length;) {
      typedTokens.set(_typedTokens[i], _typedTokenTypes[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Check if token is matched with type
  /// @param _token Token address
  /// @param _type Token type
  /// @return _isMatched Boolean value if token is stable
  function isMatchedWithType(address _token, uint256 _type) external view override returns (bool _isMatched) {
    return typedTokens.contains(_token) && typedTokens.get(_token) == _type;
  }

  /// @notice Get strategy config
  /// @param _strategy Strategy address
  /// @return _config Strategy config
  function getStrategyConfig(address _strategy, address _principalToken) external view returns (bytes memory) {
    return strategyConfigs[_strategy][_principalToken];
  }

  /// @notice Set strategy config
  /// @param _strategy Strategy address
  /// @param _config Strategy config
  function setStrategyConfig(address _strategy, address _principalToken, bytes memory _config) external onlyOwner {
    strategyConfigs[_strategy][_principalToken] = _config;
  }

  /// @notice Set max positions
  /// @param _maxPositions Max positions
  function setMaxPositions(uint8 _maxPositions) external onlyOwner {
    maxPositions = _maxPositions;
  }
}
