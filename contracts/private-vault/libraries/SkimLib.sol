// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library SkimLib {
  using SafeERC20 for IERC20;

  function snapshotBalances(address[] calldata tokens)
    internal
    view
    returns (uint256[] memory amounts, uint256 nativeBalance)
  {
    if (tokens.length > 0) {
      amounts = new uint256[](tokens.length);
      for (uint256 i; i < tokens.length; i++) {
        amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
      }
    }
    nativeBalance = address(this).balance > msg.value ? address(this).balance - msg.value : 0;
  }

  function skimSurplus(
    uint256[] memory amountsBefore,
    uint256 nativeBefore,
    address[] calldata tokens,
    address recipient
  ) internal {
    for (uint256 i; i < tokens.length; i++) {
      uint256 amountBefore = amountsBefore[i];
      uint256 amountAfter = IERC20(tokens[i]).balanceOf(address(this));
      if (amountAfter > amountBefore) IERC20(tokens[i]).safeTransfer(recipient, amountAfter - amountBefore);
    }
    uint256 nativeAfter = address(this).balance;
    if (nativeAfter > nativeBefore) {
      (bool success,) = recipient.call{ value: nativeAfter - nativeBefore }("");
      require(success, "Failed to send native token");
    }
  }
}
