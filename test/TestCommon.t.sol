// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ICommon } from "../contracts/interfaces/ICommon.sol";

interface IV3SwapRouter {
  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  /// @notice Swaps `amountIn` of one token for as much as possible of another token
  /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
  /// and swap the entire amount, enabling contracts to send tokens before calling this function.
  /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in
  /// calldata
  /// @return amountOut The amount of the received token
  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

abstract contract TestCommon is Test {
  using stdStorage for StdStorage;

  function setErc20Balance(address token, address account, uint256 amount) internal {
    stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(account).checked_write(amount);
  }

  function transferAssets(ICommon.Asset[] memory assets, address to) internal {
    for (uint256 i = 0; i < assets.length; i++) {
      if (assets[i].assetType == ICommon.AssetType.ERC20) {
        IERC20(assets[i].token).transfer(to, assets[i].amount);
      } else if (assets[i].assetType == ICommon.AssetType.ERC721) {
        address owner = IERC721(assets[i].token).ownerOf(assets[i].tokenId);
        IERC721(assets[i].token).transferFrom(owner, to, assets[i].tokenId);
      }
    }
  }
}
