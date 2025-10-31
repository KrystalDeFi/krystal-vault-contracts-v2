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
    bool vaultOwnerAsRecipient
  ) external payable {
    uint256[] memory amountsBefore;
    uint256 nativeBefore;
    if (vaultOwnerAsRecipient && withdrawTokens.length > 0) {
      amountsBefore = new uint256[](withdrawTokens.length);
      for (uint256 i; i < withdrawTokens.length; i++) {
        amountsBefore[i] = IERC20(withdrawTokens[i]).balanceOf(address(this));
      }
      nativeBefore = address(this).balance - msg.value;
    }
    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);
    if (vaultOwnerAsRecipient && withdrawTokens.length > 0) {
      address recipient = IPrivateVault(address(this)).vaultOwner();
      for (uint256 i; i < withdrawTokens.length; i++) {
        uint256 balanceAfter = IERC20(withdrawTokens[i]).balanceOf(address(this));
        if (balanceAfter > amountsBefore[i]) {
          IERC20(withdrawTokens[i]).safeTransfer(recipient, balanceAfter - amountsBefore[i]);
        }
      }
      uint256 nativeAfter = address(this).balance;
      if (nativeAfter > nativeBefore) {
        uint256 nativeAmount = nativeAfter - nativeBefore;
        (bool success,) = recipient.call{ value: nativeAmount }("");
        require(success, "Failed to send native token");
      }
    }
  }

  function execute(
    address posm,
    bytes calldata params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata approveAmounts,
    bool returnLeftOverToOwner
  ) external payable {
    require(tokens.length == approveAmounts.length);
    uint256[] memory amountsBefore;
    uint256 nativeBefore;
    if (returnLeftOverToOwner) {
      amountsBefore = new uint256[](tokens.length);
      nativeBefore = address(this).balance - msg.value;
    }
    for (uint256 i; i < tokens.length; i++) {
      if (approveAmounts[i] > 0) IERC20(tokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
      if (returnLeftOverToOwner) amountsBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
    }

    IV4UtilsRouter(v4UtilsRouter).execute{ value: ethValue }(posm, params);
    if (returnLeftOverToOwner) {
      address recipient = IPrivateVault(address(this)).vaultOwner();
      for (uint256 i; i < tokens.length; i++) {
        uint256 balanceAfter = IERC20(tokens[i]).balanceOf(address(this));
        if (balanceAfter > amountsBefore[i]) {
          IERC20(tokens[i]).safeTransfer(recipient, balanceAfter - amountsBefore[i]);
        }
      }
      uint256 nativeAfter = address(this).balance;
      if (nativeAfter > nativeBefore) {
        uint256 nativeAmount = nativeAfter - nativeBefore;
        (bool success,) = recipient.call{ value: nativeAmount }("");
        require(success, "Failed to send native token");
      }
    }
  }
}
