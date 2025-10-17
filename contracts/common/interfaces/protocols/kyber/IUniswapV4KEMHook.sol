// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IUniswapV4KEMHook {
  /**
   * @notice Claim some of equilibrium-gain tokens accrued by the hook
   * @notice Can only be called by the claimable accounts
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts) external;
}
