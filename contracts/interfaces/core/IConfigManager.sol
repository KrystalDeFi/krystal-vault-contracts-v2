// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IConfigManager is ICommon {
  event MaxPositionsSet(uint8 _maxPositions);

  event WhitelistStrategy(address[] _strategies, bool _isWhitelisted);

  event WhitelistSwapRouter(address[] _swapRouters, bool _isWhitelisted);

  event WhitelistAutomator(address[] _automators, bool _isWhitelisted);

  event SetStrategyConfig(address indexed _strategy, address indexed _principalToken, bytes _config);

  event SetTypedTokens(address[] _typedTokens, uint256[] _typedTokenTypes);

  event SetFeeConfig(bool allowDeposit, FeeConfig _feeConfig);

  function maxPositions() external view returns (uint8 _maxPositions);

  function whitelistStrategy(address[] memory _strategies, bool _isWhitelisted) external;

  function isWhitelistedStrategy(address _strategy) external view returns (bool _isWhitelisted);

  function whitelistSwapRouter(address[] memory _swapRouters, bool _isWhitelisted) external;

  function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool _isWhitelisted);

  function whitelistAutomator(address[] memory _automators, bool _isWhitelisted) external;

  function isWhitelistedAutomator(address _automator) external view returns (bool _isWhitelisted);

  function getTypedTokens() external view returns (address[] memory _typedTokens, uint256[] memory _typedTokenTypes);

  function setTypedTokens(address[] memory _typedTokens, uint256[] memory _typedTokenTypes) external;

  function isMatchedWithType(address _token, uint256 _type) external view returns (bool);

  function getStrategyConfig(address _strategy, address _principalToken) external view returns (bytes memory);

  function setStrategyConfig(address _strategy, address _principalToken, bytes memory _config) external;

  function setMaxPositions(uint8 _maxPositions) external;

  function setFeeConfig(bool allowDeposit, FeeConfig memory _feeConfig) external;

  function getFeeConfig(bool allowDeposit) external view returns (FeeConfig memory);
}
