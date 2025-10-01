// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ICLGauge } from "../../interfaces/strategies/aerodrome/ICLGauge.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract AerodromeFarmingStrategy {
  function deposit(uint256 tokenId, address clGauge) external {
    IERC721Enumerable nfpm = IERC721Enumerable(ICLGauge(clGauge).nft());
    if (tokenId == 0) {
      // deposit the last created token
      tokenId = nfpm.tokenByIndex(nfpm.totalSupply() - 1);
    }
    IERC721(nfpm).approve(clGauge, tokenId);
    ICLGauge(clGauge).deposit(tokenId);
  }

  function withdraw(uint256 tokenId, address clGauge) external {
    ICLGauge(clGauge).withdraw(tokenId);
  }

  function harvest(address clGauge, uint256 tokenId) external {
    ICLGauge(clGauge).getReward(tokenId);
  }
}
