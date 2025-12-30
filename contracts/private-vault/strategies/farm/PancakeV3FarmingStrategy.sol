// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IMasterChefV3 } from "../../../common/interfaces/protocols/pancakev3/IMasterChefV3.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CollectFee } from "../../libraries/CollectFee.sol";
import { IPrivateConfigManager } from "../../interfaces/core/IPrivateConfigManager.sol";
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PancakeV3FarmingStrategy {
  using SafeERC20 for IERC20;

  address public immutable masterChefV3;
  IPrivateConfigManager public immutable configManager;

  event PancakeV3FarmingStaked(
    address indexed nfpm, uint256 indexed tokenId, address indexed masterChefV3, address msgSender
  );
  event PancakeV3FarmingUnstaked(uint256 indexed tokenId, address indexed masterChefV3, address msgSender);
  event PancakeV3FarmingRewardsHarvested(uint256 indexed tokenId, address indexed masterChefV3, address msgSender);

  constructor(address _masterChefV3, address _configManager) {
    require(_masterChefV3 != address(0), "Invalid masterChef");
    require(_configManager != address(0), "Invalid config manager");
    masterChefV3 = _masterChefV3;
    configManager = IPrivateConfigManager(_configManager);
  }

  function deposit(uint256 tokenId) external payable {
    address nfpm = IMasterChefV3(masterChefV3).nonfungiblePositionManager();
    if (tokenId == 0) {
      uint256 totalSupply = IERC721Enumerable(nfpm).totalSupply();
      tokenId = IERC721Enumerable(nfpm).tokenByIndex(totalSupply - 1);
    }

    IERC721(nfpm).safeTransferFrom(address(this), masterChefV3, tokenId);

    emit PancakeV3FarmingStaked(nfpm, tokenId, masterChefV3, msg.sender);
  }

  function withdraw(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient)
    external
    payable
  {
    _harvest(tokenId, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);
    IMasterChefV3(masterChefV3).withdraw(tokenId, address(this));
    emit PancakeV3FarmingUnstaked(tokenId, masterChefV3, msg.sender);
  }

  function harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient) external payable {
    _harvest(tokenId, rewardFeeX64, gasFeeX64, vaultOwnerAsRecipient);
    emit PancakeV3FarmingRewardsHarvested(tokenId, masterChefV3, msg.sender);
  }

  function _harvest(uint256 tokenId, uint64 rewardFeeX64, uint64 gasFeeX64, bool vaultOwnerAsRecipient)
    internal
    returns (uint256 harvestedAmount)
  {
    address rewardToken = IMasterChefV3(masterChefV3).CAKE();
    uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

    IMasterChefV3(masterChefV3).harvest(tokenId, address(this));

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
