// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ICLGauge } from "../../interfaces/strategies/aerodrome/ICLGauge.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract AerodromeFarmingStrategy {
  address public immutable gaugeFactory;

  event AerodromeFarmingStaked(address indexed nfpm, uint256 indexed tokenId, address indexed gauge, address msgSender);
  event AerodromeFarmingUnstaked(uint256 indexed tokenId, address indexed gauge, address msgSender);
  event AerodromeFarmingRewardsHarvested(uint256 indexed tokenId, address indexed gauge, address msgSender);

  constructor(address _gaugeFactory) {
    gaugeFactory = _gaugeFactory;
  }

  function deposit(uint256 tokenId, address clGauge) external {
    require(ICLGauge(clGauge).gaugeFactory() == gaugeFactory, "IG");
    IERC721Enumerable nfpm = IERC721Enumerable(ICLGauge(clGauge).nft());
    if (tokenId == 0) {
      // deposit the last created token
      tokenId = nfpm.tokenByIndex(nfpm.totalSupply() - 1);
    }
    IERC721(nfpm).approve(clGauge, tokenId);
    ICLGauge(clGauge).deposit(tokenId);

    emit AerodromeFarmingStaked(address(nfpm), tokenId, clGauge, msg.sender);
  }

  function withdraw(uint256 tokenId, address clGauge) external {
    ICLGauge(clGauge).withdraw(tokenId);

    emit AerodromeFarmingUnstaked(tokenId, clGauge, msg.sender);
  }

  function harvest(address clGauge, uint256 tokenId) external {
    ICLGauge(clGauge).getReward(tokenId);

    emit AerodromeFarmingRewardsHarvested(tokenId, clGauge, msg.sender);
  }
}
