// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IV4UtilsRouter {
  /**
   * @notice Execute a function call on the appropriate V4Utils implementation
   * @param posm The position manager address to determine which V4Utils to use
   * @param data The encoded function call data including selector
   */
  function execute(address posm, bytes calldata data) external payable;
}
