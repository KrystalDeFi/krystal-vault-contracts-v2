// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IV3UtilsV2 as IV3Utils } from "../../interfaces/strategies/lpv3/IV3UtilsV2.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeApprovalLib } from "../../libraries/SafeApprovalLib.sol";

contract V3UtilsV2Strategy {
  using SafeApprovalLib for IERC20;

  address public immutable v3utils;

  constructor(address _v3utils) {
    v3utils = _v3utils;
  }

  function safeTransferNft(address _nfpm, uint256 tokenId, bytes calldata instructions) external {
    IERC721(_nfpm).safeTransferFrom(address(this), v3utils, tokenId, instructions);
  }

  function swapAndMint(
    IV3Utils.SwapAndMintParams calldata params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata amounts
  ) external payable returns (IV3Utils.SwapAndMintResult memory) {
    _approveTokens(tokens, amounts, v3utils);
    return IV3Utils(v3utils).swapAndMint{ value: ethValue }(params);
  }

  function swapAndIncreaseLiquidity(
    IV3Utils.SwapAndIncreaseLiquidityParams calldata params,
    uint256 ethValue,
    address[] calldata tokens,
    uint256[] calldata amounts
  ) external payable returns (IV3Utils.SwapAndIncreaseLiquidityResult memory) {
    _approveTokens(tokens, amounts, v3utils);
    return IV3Utils(v3utils).swapAndIncreaseLiquidity{ value: ethValue }(params);
  }

  function _approveTokens(address[] calldata tokens, uint256[] calldata approveAmounts, address target) internal {
    require(tokens.length == approveAmounts.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i]).safeResetAndApprove(target, approveAmounts[i]);
    }
  }
}
