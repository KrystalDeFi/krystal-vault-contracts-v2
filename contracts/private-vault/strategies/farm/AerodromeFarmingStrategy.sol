// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ICLGauge } from "../../../common/interfaces/protocols/aerodrome/ICLGauge.sol";
import { IAeroCLGauge } from "../../../common/interfaces/protocols/aerodrome/IAeroCLGauge.sol";
import { IAeroCLGaugeFactory } from "../../../common/interfaces/protocols/aerodrome/IAeroCLGaugeFactory.sol";
import { IAeroLeafVoter } from "../../../common/interfaces/protocols/aerodrome/IAeroLeafVoter.sol";
import { IAeroEmissionsHandler } from "../../../common/interfaces/protocols/aerodrome/IAeroEmissionsHandler.sol";
import { IAeroMessageOrchestrator } from "../../../common/interfaces/protocols/aerodrome/IAeroMessageOrchestrator.sol";
import { IAeroRootLocalAdapter } from "../../../common/interfaces/protocols/aerodrome/IAeroRootLocalAdapter.sol";
import { IAeroRootMessageOrchestrator } from
  "../../../common/interfaces/protocols/aerodrome/IAeroRootMessageOrchestrator.sol";
import { IAeroVoter } from "../../../common/interfaces/protocols/aerodrome/IAeroVoter.sol";
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

/// @notice Stakes vault positions in the CL gauges of one gauge factory: a legacy Aerodrome/Velodrome Slipstream
///         one, or Aero's (the merged Aerodrome + Velodrome protocol), whose gauges pay emissions through
///         `claimEmissions` instead of `getReward`.
contract AerodromeFarmingStrategy {
  using SafeERC20 for IERC20;

  address public immutable gaugeFactory;
  address public immutable nfpm;
  IPrivateConfigManager public immutable configManager;
  /// @notice Aero's LeafVoter when the gauge factory is Aero's, zero for a legacy gauge factory
  address public immutable leafVoter;
  /// @notice Token Aero gauges pay emissions in on this chain: AERO on Base, xAERO on the other chains, read from the
  ///         LeafVoter at deployment. Zero for a legacy gauge factory, whose gauges report their reward token themselves.
  address public immutable emissionToken;

  event AerodromeFarmingStaked(address indexed nfpm, uint256 indexed tokenId, address indexed gauge, address msgSender);
  event AerodromeFarmingUnstaked(uint256 indexed tokenId, address indexed gauge, address msgSender);
  event AerodromeFarmingRewardsHarvested(uint256 indexed tokenId, address indexed gauge, address msgSender);

  /// @dev A legacy gauge factory is told apart from Aero's by not having `leafVoter()`.
  constructor(address _gaugeFactory, address _configManager) {
    require(_gaugeFactory != address(0), "Invalid gauge factory");
    require(_configManager != address(0), "Invalid config manager");
    address _leafVoter = _leafVoterOf(_gaugeFactory);
    address _emissionToken;
    if (_leafVoter != address(0)) {
      _emissionToken = _emissionTokenOf(_leafVoter);
      require(_emissionToken != address(0), "Invalid emission token");
    }
    gaugeFactory = _gaugeFactory;
    nfpm = ICLGaugeFactory(_gaugeFactory).nft();
    configManager = IPrivateConfigManager(_configManager);
    leafVoter = _leafVoter;
    emissionToken = _emissionToken;
  }

  function _leafVoterOf(address _gaugeFactory) private view returns (address) {
    try IAeroCLGaugeFactory(_gaugeFactory).leafVoter() returns (address _leafVoter) {
      return _leafVoter;
    } catch {
      return address(0);
    }
  }

  /// @dev The token Aero pays emissions in on this chain. Leaf chains pay the receipt token (xAERO) that the
  ///      LeafVoter's emissions handler transfers. On Base, the root chain, the handler redeems it right away for the
  ///      root Voter's TOKEN (AERO), reached along the route a redeem takes: LeafVoter, message orchestrator, root-local
  ///      adapter, root message orchestrator, Voter. A route that breaks reverts the deployment.
  function _emissionTokenOf(address _leafVoter) private view returns (address) {
    try IAeroEmissionsHandler(IAeroLeafVoter(_leafVoter).EMISSIONS_HANDLER()).RECEIPT_TOKEN() returns (address paid) {
      return paid;
    } catch {
      address adapter = IAeroMessageOrchestrator(IAeroLeafVoter(_leafVoter).ORCHESTRATOR()).adapter();
      address voter = IAeroRootMessageOrchestrator(IAeroRootLocalAdapter(adapter).ROOT_MESSAGE_ORCHESTRATOR()).VOTER();
      return IAeroVoter(voter).TOKEN();
    }
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
    // A legacy gauge refuses deposits once killed. An Aero gauge doesn't, yet while it is inactive or has a zero
    // emission cap it pays no emissions and still takes the staked position's swap fees.
    if (leafVoter != address(0)) {
      require(
        IAeroLeafVoter(leafVoter).isActivated(clGauge) && IAeroCLGaugeFactory(gaugeFactory).emissionCap(clGauge) != 0,
        "Gauge not active"
      );
    }
    IERC721(nfpm).approve(clGauge, tokenId);
    ICLGauge(clGauge).deposit(tokenId);

    emit AerodromeFarmingStaked(nfpm, tokenId, clGauge, msg.sender);
  }

  function withdraw(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient)
    external
    payable
  {
    address clGauge = _getGaugeFromTokenId(tokenId);
    if (leafVoter == address(0)) {
      _harvest(clGauge, tokenId, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);
      ICLGauge(clGauge).withdraw(tokenId);
    } else {
      // An Aero gauge claims the position's emissions itself on withdraw, and defers them when the mint fails so that a
      // minting outage can't block the exit. Claiming first would revert the whole withdrawal in exactly that case, so
      // measure the gauge's own claim. Its fee collect moves nothing here: a staked position earns no pool fees, and
      // the gauge swept the owed ones to the vault at deposit.
      uint256 balanceBefore = IERC20(emissionToken).balanceOf(address(this));
      ICLGauge(clGauge).withdraw(tokenId);
      _distributeReward(emissionToken, balanceBefore, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);
    }

    emit AerodromeFarmingUnstaked(tokenId, clGauge, msg.sender);
  }

  /// @notice Aero only: unstake through the gauge's emergency exit, which works only while Aero governance has it
  ///         enabled. The position's accrued emissions are forfeited.
  function emergencyWithdraw(uint256 tokenId) external payable {
    require(leafVoter != address(0), "Not an Aero gauge");
    address clGauge = _getGaugeFromTokenId(tokenId);
    IAeroCLGauge(clGauge).emergencyWithdraw(tokenId);

    emit AerodromeFarmingUnstaked(tokenId, clGauge, msg.sender);
  }

  function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) external payable {
    address clGauge = _getGaugeFromTokenId(tokenId);
    _harvest(clGauge, tokenId, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);

    emit AerodromeFarmingRewardsHarvested(tokenId, clGauge, msg.sender);
  }

  function _harvest(address clGauge, uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient)
    internal
    returns (uint256 harvestedAmount)
  {
    if (leafVoter == address(0)) {
      address rewardToken = ICLGauge(clGauge).rewardToken();
      uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));
      ICLGauge(clGauge).getReward(tokenId);
      return _distributeReward(rewardToken, balanceBefore, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);
    }

    // Every Aero claim also pays out the vault's deferred emissions. A withdrawn position can no longer be named in a
    // claim, so for one the list stays empty and only the deferred emissions are claimed.
    uint256[] memory tokenIds;
    if (ICLGauge(clGauge).stakedContains(address(this), tokenId)) {
      tokenIds = new uint256[](1);
      tokenIds[0] = tokenId;
    }
    uint256 emissionsBefore = IERC20(emissionToken).balanceOf(address(this));
    IAeroCLGauge(clGauge).claimEmissions(address(this), address(this), tokenIds);
    harvestedAmount = _distributeReward(emissionToken, emissionsBefore, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);
  }

  /// @dev Takes the fees from what the claim paid, then forwards the rest to the vault owner when asked to.
  function _distributeReward(
    address rewardToken,
    uint256 balanceBefore,
    uint64 rewardFeeX64,
    uint64 gasFeeX64,
    bool vaultOwnerAsRecipient
  ) internal returns (uint256 harvestedAmount) {
    harvestedAmount = _handleReward(rewardToken, balanceBefore, rewardFeeX64, gasFeeX64);
    if (vaultOwnerAsRecipient && harvestedAmount > 0) {
      address rewardRecipient = IPrivateVault(address(this)).vaultOwner();
      IERC20(rewardToken).safeTransfer(rewardRecipient, harvestedAmount);
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
