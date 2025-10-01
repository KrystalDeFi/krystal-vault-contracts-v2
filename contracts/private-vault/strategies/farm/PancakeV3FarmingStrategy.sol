// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IMasterChefV3 } from "../../interfaces/strategies/pancakev3/IMasterChefV3.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract PancakeV3FarmingStrategy {
  address public immutable masterChefV3;

  constructor(address _masterChefV3) {
    masterChefV3 = _masterChefV3;
  }

  function deposit(uint256 tokenId) external {
    address nfpm = IMasterChefV3(masterChefV3).nonfungiblePositionManager();
    if (tokenId == 0) {
      uint256 totalSupply = IERC721Enumerable(nfpm).totalSupply();
      tokenId = IERC721Enumerable(nfpm).tokenByIndex(totalSupply - 1);
    }

    IERC721(nfpm).safeTransferFrom(address(this), masterChefV3, tokenId);
  }

  function withdraw(uint256 tokenId) external {
    IMasterChefV3(masterChefV3).withdraw(tokenId, address(this));
  }

  function harvest(uint256 tokenId) external {
    IMasterChefV3(masterChefV3).harvest(tokenId, address(this));
  }
}
