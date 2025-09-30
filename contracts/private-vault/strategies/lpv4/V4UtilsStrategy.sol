// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV4UtilsRouter } from "../../interfaces/strategies/lpv4/IV4UtilsRouter.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../libraries/SafeApprovalLib.sol";

contract V4UtilsStrategy {
  using SafeApprovalLib for IERC20;

  address public immutable v4UtilsRouter;

  function safeTransferNft(address posm, uint256 tokenId, bytes calldata instruction) external {
    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);
  }

  function execute(
    address posm,
    bytes calldata params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata approveAmounts
  ) external {
    require(tokens.length == approveAmounts.length);
    for (uint256 i; i < tokens.length; i++) {
      if (approveAmounts[i] > 0) IERC20(tokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
    }

    IV4UtilsRouter(v4UtilsRouter).execute{ value: ethValue }(posm, params);
  }
}
