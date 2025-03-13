// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IWhitelistManager is ICommon {
  function whitelistStrategy(address[] memory _strategies, bool _isWhitelisted) external;

  function isWhitelistedStrategy(address _strategy) external view returns (bool _isWhitelisted);

  function whitelistSwapRouter(address[] memory _swapRouters, bool _isWhitelisted) external;

  function isWhitelistedSwapRouter(address _swapRouter) external view returns (bool _isWhitelisted);
}
