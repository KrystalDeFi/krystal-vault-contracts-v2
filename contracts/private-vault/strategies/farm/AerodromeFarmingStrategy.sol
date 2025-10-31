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
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AerodromeFarmingStrategy {
  using SafeERC20 for IERC20;

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

  function deposit(uint256 tokenId) external payable {
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

  function withdraw(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, address rewardRecipient) external payable {
    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvest(clGauge, tokenId, rewardFeeX64, gasFeeX64, rewardRecipient);
    ICLGauge(clGauge).withdraw(tokenId);

    emit AerodromeFarmingUnstaked(tokenId, clGauge, msg.sender);
  }

  function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, address rewardRecipient) external payable {
    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvest(clGauge, tokenId, rewardFeeX64, gasFeeX64, rewardRecipient);

    emit AerodromeFarmingRewardsHarvested(tokenId, clGauge, msg.sender);
  }

  function _harvest(address clGauge, uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, address rewardRecipient)
    internal
    returns (uint256 harvestedAmount)
  {
    address rewardToken = ICLGauge(clGauge).rewardToken();
    uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

    ICLGauge(clGauge).getReward(tokenId);

    harvestedAmount = _handleReward(rewardToken, balanceBefore, rewardFeeX64, gasFeeX64);
    if (rewardRecipient != address(0) && rewardRecipient != address(this)) {
      require(rewardRecipient == IPrivateVault(address(this)).vaultOwner(), "Invalid recipient");
      if (harvestedAmount > 0) IERC20(rewardToken).safeTransfer(rewardRecipient, harvestedAmount);
    }
  }

  function _handleReward(address rewardToken, uint256 balanceBefore, uint64 rewardFeeX64, uint64 gasFeeX64)
    internal
    returns (uint256 harvestedAmount)
  {
    uint256 balanceAfter = IERC20(rewardToken).balanceOf(address(this));
    if (balanceAfter <= balanceBefore) return 0;

    harvestedAmount = balanceAfter - balanceBefore;
    if (harvestedAmount == 0) return 0;
    uint256 feeAmount;

    if (rewardFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(), rewardToken, harvestedAmount, rewardFeeX64, CollectFee.FeeType.FARM_REWARD
      );
    }

    if (gasFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(), rewardToken, harvestedAmount, gasFeeX64, CollectFee.FeeType.GAS
      );
    }
    harvestedAmount -= feeAmount;
  }
}
