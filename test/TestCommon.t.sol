// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { AssetLib } from "../contracts/libraries/AssetLib.sol";

address constant WETH = 0x4200000000000000000000000000000000000006;
address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
address constant USER = 0xaaA72CEd70ce1C4E0c36443F2d236049A9640697;
address constant PLAYER_1 = 0x1234567890123456789012345678901234567891;
address constant PLAYER_2 = 0x1234567890123456789012345678901234567892;
address constant BIGHAND_PLAYER = 0xaaaa567890123456789012345678901234567893;
address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant MORPHO = 0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842;
address constant NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
address constant SUSHI_NFPM = 0x80C7DD17B01855a6D2347444a0FCC36136a314de;
address constant PANCAKE_NFPM = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
address constant HYPER_NFPM = 0x6eDA206207c09e5428F281761DdC0D300851fBC8;
address constant HYPER_PROJECTX_NFPM = 0xeaD19AE861c29bBb2101E834922B2FEee69B9091;
address constant HYPER_UPHEAVAL_NFPM = 0xC8352A2EbA29F4d9BD4221c07D3461BaCc779088;

// address constant UNISWAP_NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

address constant PLATFORM_WALLET = 0x0000000000000000000000000000000000000010;

address constant NULL_ADDRESS = 0x0000000000000000000000000000000000000000;

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

  uint256 public TOLERANCE = 0.005 ether; // = 0.5%

  function setErc20Balance(address token, address account, uint256 amount) internal {
    stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(account).checked_write(amount);
  }

  function transferAsset(AssetLib.Asset memory asset, address to) internal {
    if (asset.assetType == AssetLib.AssetType.ERC20) {
      IERC20(asset.token).transfer(to, asset.amount);
    } else if (asset.assetType == AssetLib.AssetType.ERC721) {
      address owner = IERC721(asset.token).ownerOf(asset.tokenId);
      IERC721(asset.token).transferFrom(owner, to, asset.tokenId);
    }
  }

  function transferAssets(AssetLib.Asset[] memory assets, address to) internal {
    for (uint256 i = 0; i < assets.length; i++) {
      transferAsset(assets[i], to);
    }
  }
}
