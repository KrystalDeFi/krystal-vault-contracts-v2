// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SafeApprovalLib
 * @notice Library for safe token approvals with reset functionality
 * @dev Provides utilities for safely approving tokens, including reset-and-approve pattern
 */
library SafeApprovalLib {
  error ApproveFailed();

  /**
   * @notice Safe approve function that handles non-standard ERC20 tokens
   * @param token The token to approve
   * @param spender The spender address
   * @param value The amount to approve
   */
  function safeApprove(IERC20 token, address spender, uint256 value) internal {
    (bool success, bytes memory returnData) =
      address(token).call(abi.encodeWithSelector(token.approve.selector, spender, value));
    require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), ApproveFailed());
  }

  /**
   * @notice Safe reset and approve function to handle tokens that require allowance to be 0 before setting new value
   * @param token The token to approve
   * @param spender The spender address
   * @param value The amount to approve
   * @dev First resets allowance to 0, then sets to desired value
   */
  function safeResetAndApprove(IERC20 token, address spender, uint256 value) internal {
    // First reset to 0 to handle tokens like USDT that require this
    safeApprove(token, spender, 0);

    // Then approve the desired amount (if non-zero)
    if (value > 0) safeApprove(token, spender, value);
  }

  /**
   * @notice Safe approve with automatic reset if needed
   * @param token The token to approve
   * @param spender The spender address
   * @param value The amount to approve
   * @dev Attempts normal approve first, if it fails, tries reset-and-approve pattern
   */
  function safeApproveWithFallback(IERC20 token, address spender, uint256 value) internal {
    // Try normal approve first
    (bool success, bytes memory returnData) =
      address(token).call(abi.encodeWithSelector(token.approve.selector, spender, value));

    bool approveSuccess = success && (returnData.length == 0 || abi.decode(returnData, (bool)));

    if (!approveSuccess) {
      // If normal approve failed, try reset-and-approve pattern
      safeResetAndApprove(token, spender, value);
    }
  }
}
