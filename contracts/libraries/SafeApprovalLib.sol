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
    if (value == 0) {
      // some token does not allow approve(0) so we skip check for this case
      return;
    }

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
    if (value == 0) return;
    // First reset to 0 to handle tokens like USDT that require this
    safeApprove(token, spender, 0);

    // Then approve the desired amount
    safeApprove(token, spender, value);
  }
}
