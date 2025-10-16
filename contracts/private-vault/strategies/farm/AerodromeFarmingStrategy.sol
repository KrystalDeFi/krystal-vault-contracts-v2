// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ICLGauge } from "../../../common/interfaces/protocols/aerodrome/ICLGauge.sol";
import { INonfungiblePositionManager } from
  "../../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import { ICLGaugeFactory } from "../../../common/interfaces/protocols/aerodrome/ICLGaugeFactory.sol";
import { ICLPool } from "../../../common/interfaces/protocols/aerodrome/ICLPool.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ICLFactory } from "../../../common/interfaces/protocols/aerodrome/ICLFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollectFee } from "../../libraries/CollectFee.sol";
import { IPrivateConfigManager } from "../../interfaces/core/IPrivateConfigManager.sol";

contract AerodromeFarmingStrategy {
  address public immutable gaugeFactory;
  address public immutable nfpm;
  IPrivateConfigManager public immutable configManager;

  event AerodromeFarmingStaked(address indexed nfpm, uint256 indexed tokenId, address indexed gauge, address msgSender);
  event AerodromeFarmingUnstaked(uint256 indexed tokenId, address indexed gauge, address msgSender);
  event AerodromeFarmingRewardsHarvested(uint256 indexed tokenId, address indexed gauge, address msgSender);

  constructor(address _gaugeFactory, address _configManager) {
    require(_gaugeFactory != address(0), "Invalid gauge factory");
    require(_configManager != address(0), "Invalid config manager");
    gaugeFactory = _gaugeFactory;
    nfpm = ICLGaugeFactory(_gaugeFactory).nft();
    configManager = IPrivateConfigManager(_configManager);
  }

  function _getGaugeFromTokenId(uint256 tokenId) internal view returns (address gauge) {
    // Get position data from NFPM
    (,, address token0, address token1, int24 tickSpacing,,,,,,,) = INonfungiblePositionManager(nfpm).positions(tokenId);

    // Get factory from NFPM
    address factory = INonfungiblePositionManager(nfpm).factory();

    // Ensure tokens are ordered correctly (token0 < token1)
    if (token0 > token1) (token0, token1) = (token1, token0);

    // Get pool from factory
    address pool = ICLFactory(factory).getPool(token0, token1, tickSpacing);
    require(pool != address(0), "Pool not found");

    // Get gauge from pool
    gauge = ICLPool(pool).gauge();
    require(gauge != address(0), "Gauge not found");
  }

  function deposit(uint256 tokenId) external {
    if (tokenId == 0) {
      // deposit the last created token
      IERC721Enumerable nfpmEnum = IERC721Enumerable(nfpm);
      tokenId = nfpmEnum.tokenByIndex(nfpmEnum.totalSupply() - 1);
    }

    address clGauge = _getGaugeFromTokenId(tokenId);
    IERC721(nfpm).approve(clGauge, tokenId);
    ICLGauge(clGauge).deposit(tokenId);

    emit AerodromeFarmingStaked(nfpm, tokenId, clGauge, msg.sender);
  }

  function withdraw(uint256 tokenId, uint16 feeBps) external {
    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvest(clGauge, tokenId, feeBps);
    ICLGauge(clGauge).withdraw(tokenId);

    emit AerodromeFarmingUnstaked(tokenId, clGauge, msg.sender);
  }

  function harvest(uint256 tokenId, uint16 feeBps) external {
    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvest(clGauge, tokenId, feeBps);

    emit AerodromeFarmingRewardsHarvested(tokenId, clGauge, msg.sender);
  }

  function _harvest(address clGauge, uint256 tokenId, uint16 feeBps) internal {
    address rewardToken = ICLGauge(clGauge).rewardToken();
    uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

    ICLGauge(clGauge).getReward(tokenId);

    _handleReward(rewardToken, balanceBefore, feeBps);
  }

  function _handleReward(address rewardToken, uint256 balanceBefore, uint16 feeBps) internal {
    uint256 balanceAfter = IERC20(rewardToken).balanceOf(address(this));
    if (balanceAfter <= balanceBefore) return;

    uint256 harvestedAmount = balanceAfter - balanceBefore;
    if (feeBps == 0) return;

    CollectFee.collect(
      configManager.feeRecipient(), rewardToken, harvestedAmount, feeBps, CollectFee.FARM_REWARD_FEE_TYPE
    );
  }
}
