// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IRamsesVoter } from "../../../common/interfaces/protocols/ramses/IRamsesVoter.sol";
import { IRamsesV3PositionManager } from "../../../common/interfaces/protocols/ramses/IRamsesV3PositionManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollectFee } from "../../libraries/CollectFee.sol";
import { IPrivateConfigManager } from "../../interfaces/core/IPrivateConfigManager.sol";
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Claims the RAM vault positions earn in Ramses CL gauges. Ramses gauges are non-custodial: a position earns
///         while the vault holds it, so there is nothing to stake or unstake, only rewards to claim through the
///         position manager.
contract RamsesFarmingStrategy {
  using SafeERC20 for IERC20;

  /// @notice The Ramses CL position manager, read from the Voter at deployment
  address public immutable nfpm;
  /// @notice RAM: the token Ramses gauges pay emissions in
  address public immutable rewardToken;
  IPrivateConfigManager public immutable configManager;

  event RamsesFarmingRewardsHarvested(
    uint256 indexed tokenId, address indexed nfpm, uint256 harvestedAmount, address msgSender
  );

  constructor(address _voter, address _configManager) {
    require(_voter != address(0), "Invalid voter");
    require(_configManager != address(0), "Invalid config manager");
    address _nfpm = IRamsesVoter(_voter).nfpManager();
    address _rewardToken = IRamsesVoter(_voter).ram();
    require(_nfpm != address(0) && _rewardToken != address(0), "Invalid voter");
    nfpm = _nfpm;
    rewardToken = _rewardToken;
    configManager = IPrivateConfigManager(_configManager);
  }

  /// @notice Claim the position's RAM, take the fees and optionally forward the rest to the vault owner.
  /// @dev Reverts when the position's pool has no gauge. Claims RAM only: xRAM can't be transferred out of the vault.
  ///      Measures what arrived, so a claim the gauge forfeits (made too soon after a liquidity change, or flagged by
  ///      Ramses' reward validator) yields nothing and charges nothing instead of reverting.
  function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient)
    external
    payable
  {
    uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));
    address[] memory tokens = new address[](1);
    tokens[0] = rewardToken;
    IRamsesV3PositionManager(nfpm).getReward(tokenId, tokens);

    uint256 claimedAmount = IERC20(rewardToken).balanceOf(address(this)) - balanceBefore;
    uint256 harvestedAmount = _handleReward(claimedAmount, rewardFeeX64, gasFeeX64);
    if (vaultOwnerAsRecipient && harvestedAmount > 0) {
      IERC20(rewardToken).safeTransfer(IPrivateVault(address(this)).vaultOwner(), harvestedAmount);
    }

    emit RamsesFarmingRewardsHarvested(tokenId, nfpm, claimedAmount, msg.sender);
  }

  function _handleReward(uint256 claimedAmount, uint64 rewardFeeX64, uint64 gasFeeX64)
    internal
    returns (uint256 harvestedAmount)
  {
    if (claimedAmount == 0) return 0;
    uint256 feeAmount;

    if (rewardFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(), rewardToken, claimedAmount, rewardFeeX64, CollectFee.FeeType.FARM_REWARD
      );
    }

    if (gasFeeX64 > 0) {
      feeAmount += CollectFee.collect(
        configManager.feeRecipient(), rewardToken, claimedAmount, gasFeeX64, CollectFee.FeeType.GAS
      );
    }
    harvestedAmount = claimedAmount - feeAmount;
  }
}
