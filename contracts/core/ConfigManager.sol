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
            tickWidthMin: 20,
            tickWidthTypedMin: 10
          },
          // Wide
          {
            tickWidthMin: 10,
            tickWidthTypedMin: 5
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
  int24 public override maxHarvestSlippage = 500; // ~5%

  FeeConfig private publicVaultFeeConfig;
  FeeConfig private privateVaultFeeConfig;

  constructor(
    address _owner,
    address[] memory _whitelistAutomator,
    address[] memory _typedTokens,
    uint256[] memory _typedTokenTypes
  ) Ownable(_owner) {
    uint256 length = _typedTokens.length;

    for (uint256 i; i < length;) {
      typedTokens.set(_typedTokens[i], _typedTokenTypes[i]);

      unchecked {
        i++;
      }
    }

    length = _whitelistAutomator.length;

    for (uint256 i; i < length;) {
      whitelistAutomators[_whitelistAutomator[i]] = true;

      unchecked {
        i++;
      }
    }
  }

  /// @notice Whitelist strategy
  /// @param _strategies Array of strategy addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistStrategy(address[] calldata _strategies, bool _isWhitelisted) external override onlyOwner {
    uint256 length = _strategies.length;

    for (uint256 i; i < length;) {
      whitelistStrategies[_strategies[i]] = _isWhitelisted;

      unchecked {
        i++;
      }
    }

    emit WhitelistStrategy(_strategies, _isWhitelisted);
  }

  /// @notice Check if strategy is whitelisted
  /// @param _strategy Strategy address
  /// @return _isWhitelisted Boolean value if strategy is whitelisted
  function isWhitelistedStrategy(address _strategy) external view override returns (bool) {
    return whitelistStrategies[_strategy];
  }

  /// @notice Whitelist swap router
  /// @param _swapRouters Array of swap router addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistSwapRouter(address[] calldata _swapRouters, bool _isWhitelisted) external override onlyOwner {
    uint256 length = _swapRouters.length;

    for (uint256 i; i < length;) {
      whitelistSwapRouters[_swapRouters[i]] = _isWhitelisted;

      unchecked {
        i++;
      }
    }

    emit WhitelistSwapRouter(_swapRouters, _isWhitelisted);
  }

  /// @notice Check if swap router is whitelisted
  /// @param _swapRouter Swap router address
  /// @return _isWhitelisted Boolean value if swap router is whitelisted
  function isWhitelistedSwapRouter(address _swapRouter) external view override returns (bool) {
    return whitelistSwapRouters[_swapRouter];
  }

  /// @notice Whitelist automator
  /// @param _automators Array of automator addresses
  /// @param _isWhitelisted Boolean value to whitelist or unwhitelist
  function whitelistAutomator(address[] calldata _automators, bool _isWhitelisted) external override onlyOwner {
    uint256 length = _automators.length;

    for (uint256 i; i < length;) {
      whitelistAutomators[_automators[i]] = _isWhitelisted;

      unchecked {
        i++;
      }
    }

    emit WhitelistAutomator(_automators, _isWhitelisted);
  }

  /// @notice Check if automator is whitelisted
  /// @param _automator Automator address
  /// @return _isWhitelisted Boolean value if automator is whitelisted
  function isWhitelistedAutomator(address _automator) external view override returns (bool) {
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

    for (uint256 i; i < length;) {
      (_typedTokens[i], _typedTokenTypes[i]) = typedTokens.at(i);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Get typed token type
  /// @param _token Token address
  /// @return _type Token type
  function getTypedToken(address _token) external view override returns (uint256 _type) {
    if (!typedTokens.contains(_token)) _type = 0;
    else _type = typedTokens.get(_token);
  }

  /// @notice Set typed tokens
  /// @param _typedTokens Array of typed token addresses
  /// @param _typedTokenTypes Array of typed token types
  function setTypedTokens(address[] calldata _typedTokens, uint256[] calldata _typedTokenTypes) external onlyOwner {
    uint256 length = _typedTokens.length;

    for (uint256 i; i < length;) {
      typedTokens.set(_typedTokens[i], _typedTokenTypes[i]);

      unchecked {
        i++;
      }
    }

    emit SetTypedTokens(_typedTokens, _typedTokenTypes);
  }

  /// @notice Check if token is matched with type
  /// @param _token Token address
  /// @param _type Token type
  /// @return _isMatched Boolean value if token is stable
  function isMatchedWithType(address _token, uint256 _type) external view override returns (bool) {
    return typedTokens.contains(_token) && typedTokens.get(_token) == _type;
  }

  /// @notice Get strategy config
  /// @param _strategy Strategy address
  /// @param _principalToken Principal token address
  /// @return _config Strategy config
  function getStrategyConfig(address _strategy, address _principalToken) external view returns (bytes memory) {
    return strategyConfigs[_strategy][_principalToken];
  }

  /// @notice Set strategy config
  /// @param _strategy Strategy address
  /// @param _principalToken Principal token address
  /// @param _config Strategy config
  function setStrategyConfig(address _strategy, address _principalToken, bytes calldata _config) external onlyOwner {
    strategyConfigs[_strategy][_principalToken] = _config;

    emit SetStrategyConfig(_strategy, _principalToken, _config);
  }

  /// @notice Set max positions
  /// @param _maxPositions Max positions
  function setMaxPositions(uint8 _maxPositions) external onlyOwner {
    maxPositions = _maxPositions;

    emit MaxPositionsSet(_maxPositions);
  }

  /// @notice Set max harvest slippage
  /// @param _maxHarvestSlippage Max harvest slippage
  function setMaxHarvestSlippage(int24 _maxHarvestSlippage) external onlyOwner {
    maxHarvestSlippage = _maxHarvestSlippage;

    emit MaxHarvestSlippageSet(_maxHarvestSlippage);
  }

  /// @notice Set fee config
  /// @param allowDeposit Boolean value to set fee config for public or private vault
  /// @param _feeConfig Fee config
  function setFeeConfig(bool allowDeposit, FeeConfig calldata _feeConfig) external onlyOwner {
    require(_feeConfig.vaultOwnerFeeBasisPoint < 2000, InvalidFeeConfig());
    require(_feeConfig.platformFeeBasisPoint < 2000, InvalidFeeConfig());
    require(_feeConfig.gasFeeX64 < 3_689_348_814_741_910_528, InvalidFeeConfig()); // 20%

    if (allowDeposit) publicVaultFeeConfig = _feeConfig;
    else privateVaultFeeConfig = _feeConfig;

    emit SetFeeConfig(allowDeposit, _feeConfig);
  }

  /// @notice Get fee config
  /// @param allowDeposit Boolean value to get fee config for public or private vault
  /// @return _feeConfig Fee config
  function getFeeConfig(bool allowDeposit) external view returns (FeeConfig memory) {
    return allowDeposit ? publicVaultFeeConfig : privateVaultFeeConfig;
  }
}
