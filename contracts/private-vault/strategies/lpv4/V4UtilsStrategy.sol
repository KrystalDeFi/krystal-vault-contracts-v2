// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV4UtilsRouter } from "../../interfaces/strategies/lpv4/IV4UtilsRouter.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../libraries/SafeApprovalLib.sol";
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SkimLib } from "../../libraries/SkimLib.sol";

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
    bool skimSurplusToVaultOwner
  ) external payable {
    uint256[] memory amountsBefore;
    uint256 nativeBalanceBefore;
    if (skimSurplusToVaultOwner) (amountsBefore, nativeBalanceBefore) = SkimLib.snapshotBalances(withdrawTokens);

    IERC721(posm).safeTransferFrom(address(this), v4UtilsRouter, tokenId, instruction);

    if (skimSurplusToVaultOwner) {
      SkimLib.skimSurplus(amountsBefore, nativeBalanceBefore, withdrawTokens, IPrivateVault(address(this)).vaultOwner());
    }
  }

  function execute(
    address posm,
    uint256 tokenId,
    bytes calldata params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata approveAmounts,
    bool returnLeftOverToOwner
  ) external payable {
    require(tokens.length == approveAmounts.length);
    for (uint256 i; i < tokens.length; i++) {
      if (approveAmounts[i] > 0) IERC20(tokens[i]).safeResetAndApprove(v4UtilsRouter, approveAmounts[i]);
    }
    uint256[] memory amountsBefore;
    uint256 nativeBefore;
    if (returnLeftOverToOwner) (amountsBefore, nativeBefore) = SkimLib.snapshotBalances(tokens);

    if (tokenId != 0) IERC721(posm).approve(v4UtilsRouter, tokenId);
    IV4UtilsRouter(v4UtilsRouter).execute{ value: ethValue }(posm, params);

    if (returnLeftOverToOwner) {
      SkimLib.skimSurplus(amountsBefore, nativeBefore, tokens, IPrivateVault(address(this)).vaultOwner());
    }
  }
}
