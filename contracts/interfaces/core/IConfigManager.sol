// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IConfigManager is ICommon {
  function maxPositions() external view returns (uint8);

  function whitelistStrategy(address[] memory _strategies, bool _isWhitelisted) external;

  function isWhitelistedStrategy(address _strategy) external view returns (bool _isWhitelisted);

  function whitelistSwapRouter(address[] memory _swapRouters, bool _isWhitelisted) external;

  function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool _isWhitelisted);

  function whitelistAutomator(address[] memory _automators, bool _isWhitelisted) external;

  function isWhitelistedAutomator(address _automator) external view returns (bool _isWhitelisted);

  function setStableTokens(address[] memory _stableTokens, bool _isStable) external;

  function isStableToken(address _token) external view returns (bool _isStableToken);

  function setPeggedTokens(address[] memory _peggedTokens, bool _isPegged) external;

  function isPeggedToken(address _token) external view returns (bool _isPeggedToken);

  function getStrategyConfig(address _strategy, address _principalToken) external view returns (bytes memory);

  function setStrategyConfig(address _strategy, address _principalToken, bytes memory _config) external;

  function setMaxPositions(uint8 _maxPositions) external;
}
