// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../libraries/SafeApprovalLib.sol";
import { IPrivateCommon } from "../../interfaces/core/IPrivateCommon.sol";

/**
 * @title MultiSwapStrategy
 * @notice Best-effort batch swaps through a fixed swap router, mainly used to sweep dust tokens left over from LP
 * actions. A failing swap is skipped instead of reverting, so it can never undo the rest of the vault multicall.
 */
contract MultiSwapStrategy {
  using SafeApprovalLib for IERC20;

  struct SwapParams {
    // token to sell, address(0) for the native token
    address tokenIn;
    // max amount the swap router may spend: the ERC20 allowance, or the value sent for the native token
    uint256 amountIn;
    // calldata for the swap router, which must enforce the slippage limit and the output recipient
    bytes swapData;
  }

  address public immutable swapRouter;

  event SwapAttempted(uint256 index, address indexed tokenIn, uint256 amountIn, bool success);

  constructor(address _swapRouter) {
    require(_swapRouter != address(0), IPrivateCommon.ZeroAddress());
    swapRouter = _swapRouter;
  }

  /// @notice Executes `swaps` in order without checking whether each swap succeeds
  /// @dev Entries with a zero `amountIn` or empty `swapData` are skipped. The router allowance is reset to zero after
  /// every attempt, so a failed or partially filled swap never leaves a dangling approval.
  function multiSwap(SwapParams[] calldata swaps) external payable {
    for (uint256 i; i < swaps.length; i++) {
      SwapParams calldata params = swaps[i];
      if (params.amountIn == 0 || params.swapData.length == 0) continue;

      bool success;
      if (params.tokenIn == address(0)) {
        (success, ) = swapRouter.call{ value: params.amountIn }(params.swapData);
      } else {
        IERC20(params.tokenIn).safeResetAndApprove(swapRouter, params.amountIn);
        (success, ) = swapRouter.call(params.swapData);
        IERC20(params.tokenIn).safeApprove(swapRouter, 0);
      }

      emit SwapAttempted(i, params.tokenIn, params.amountIn, success);
    }
  }
}
