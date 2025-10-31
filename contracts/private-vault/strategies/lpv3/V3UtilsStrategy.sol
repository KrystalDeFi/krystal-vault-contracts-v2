// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3Utils } from "../../interfaces/strategies/lpv3/IV3Utils.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../libraries/SafeApprovalLib.sol";
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract V3UtilsStrategy {
  using SafeApprovalLib for IERC20;
  using SafeERC20 for IERC20;

  address public immutable v3utils;

  constructor(address _v3utils) {
    v3utils = _v3utils;
  }

  function safeTransferNft(address _nfpm, uint256 tokenId, IV3Utils.Instructions memory instructions) external payable {
    require(
      instructions.recipient == address(this) || instructions.recipient == IPrivateVault(address(this)).vaultOwner()
    );
    IERC721(_nfpm).safeTransferFrom(address(this), v3utils, tokenId, abi.encode(instructions));
  }

  function swapAndMint(
    IV3Utils.SwapAndMintParams memory params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bool returnLeftOverToOwner
  ) external payable returns (IV3Utils.SwapAndMintResult memory result) {
    params.recipient = address(this);
    _approveTokens(tokens, amounts, v3utils);
    uint256[] memory amountsBefore;
    uint256 nativeBefore;
    if (returnLeftOverToOwner) {
      amountsBefore = new uint256[](tokens.length);
      for (uint256 i; i < tokens.length; i++) {
        amountsBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
      }
      nativeBefore = address(this).balance - msg.value;
    }
    result = IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);
    if (returnLeftOverToOwner) {
      address recipient = IPrivateVault(address(this)).vaultOwner();
      for (uint256 i; i < tokens.length; i++) {
        uint256 amount = IERC20(tokens[i]).balanceOf(address(this)) - amountsBefore[i];
        if (amount > 0) IERC20(tokens[i]).safeTransfer(recipient, amount);
      }
      uint256 nativeAmount = address(this).balance - nativeBefore;
      (bool success,) = recipient.call{ value: nativeAmount }("");
      require(success, "Failed to send native token");
    }
  }

  function swapAndIncreaseLiquidity(
    IV3Utils.SwapAndIncreaseLiquidityParams memory params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bool returnLeftOverToOwner
  ) external payable returns (IV3Utils.SwapAndIncreaseLiquidityResult memory result) {
    params.recipient = address(this);
    _approveTokens(tokens, amounts, v3utils);
    uint256[] memory amountsBefore;
    uint256 nativeBefore;
    if (returnLeftOverToOwner) {
      amountsBefore = new uint256[](tokens.length);
      for (uint256 i; i < tokens.length; i++) {
        amountsBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
      }
      nativeBefore = address(this).balance - msg.value;
    }

    result = IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);
    if (returnLeftOverToOwner) {
      address recipient = IPrivateVault(address(this)).vaultOwner();
      for (uint256 i; i < tokens.length; i++) {
        uint256 amount = IERC20(tokens[i]).balanceOf(address(this)) - amountsBefore[i];
        if (amount > 0) IERC20(tokens[i]).safeTransfer(recipient, amount);
      }
      uint256 nativeAmount = address(this).balance - nativeBefore;
      (bool success,) = recipient.call{ value: nativeAmount }("");
      require(success, "Failed to send native token");
    }
  }

  function _approveTokens(address[] calldata tokens, uint256[] calldata approveAmounts, address target) internal {
    require(tokens.length == approveAmounts.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i]).safeResetAndApprove(target, approveAmounts[i]);
    }
  }
}
