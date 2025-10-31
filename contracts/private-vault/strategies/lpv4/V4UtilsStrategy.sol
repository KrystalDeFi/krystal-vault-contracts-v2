// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV4UtilsRouter } from "../../interfaces/strategies/lpv4/IV4UtilsRouter.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../libraries/SafeApprovalLib.sol";
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract V4UtilsStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable v4UtilsRouter;

  constructor(address _v4UtilsRouter) {
    v4UtilsRouter = _v4UtilsRouter;
  }

  function safeTransferNft(
    address posm,
    uint256 tokenId,
    bytes calldata instruction,
    address[] calldata withdrawTokens,
    address recipient
  ) external payable {
    uint256[] memory amountsBefore;
    if (recipient != address(0) && recipient != address(this) && withdrawTokens.length > 0) {
      require(recipient == IPrivateVault(address(this)).vaultOwner(), "Invalid recipient");
      amountsBefore = new uint256[](withdrawTokens.length);
      for (uint256 i; i < withdrawTokens.length; i++) {
        amountsBefore[i] = IERC20(withdrawTokens[i]).balanceOf(address(this));
      }
    }
    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);
    if (recipient != address(0) && recipient != address(this) && withdrawTokens.length > 0) {
      for (uint256 i; i < withdrawTokens.length; i++) {
        uint256 amount = IERC20(withdrawTokens[i]).balanceOf(address(this)) - amountsBefore[i];
        if (amount > 0) IERC20(withdrawTokens[i]).safeTransfer(recipient, amount);
      }
    }
  }

  function execute(
    address posm,
    bytes calldata params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata approveAmounts
  ) external payable {
    require(tokens.length == approveAmounts.length);
    for (uint256 i; i < tokens.length; i++) {
      if (approveAmounts[i] > 0) IERC20(tokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
    }

    IV4UtilsRouter(v4UtilsRouter).execute{ value: ethValue }(posm, params);
  }
}
