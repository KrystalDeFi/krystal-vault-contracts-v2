// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ICommon.sol";

interface IWhitelistManager is ICommon {
  function whitelistStrategy(address[] memory _strategies, bool _isWhitelisted) external;

  function isWhitelisted(address _strategy) external view returns (bool _isWhitelisted);
}
