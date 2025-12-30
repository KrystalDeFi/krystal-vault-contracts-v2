// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IUniswapV4KEMHook } from "../../../common/interfaces/protocols/kyber/IUniswapV4KEMHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrivateConfigManager } from "../../interfaces/core/IPrivateConfigManager.sol";
import { CollectFee } from "../../libraries/CollectFee.sol";
import { IPrivateVault } from "../../interfaces/core/IPrivateVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract KyberFairFlowStrategy {
  using SafeERC20 for IERC20;

  address public immutable uniswapV4KEMHook;
  IPrivateConfigManager public immutable configManager;

  error InvalidInputLength();

  event FairFlowRewardClaim(address hook, address token, uint256 amount);

  constructor(address _uniswapV4KEMHook, address _configManager) {
    uniswapV4KEMHook = _uniswapV4KEMHook;
    configManager = IPrivateConfigManager(_configManager);
  }

  function claimFairFlowReward(
    address token,
    uint256 amount,
    uint64 rewardFeeX64,
    uint64 gasFeeX64,
    bool vaultOwnerAsRecipient
  ) external payable {
    address[] memory tokens = new address[](1);
    tokens[0] = token;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    uint256 reward = IERC20(token).balanceOf(address(this));
    IUniswapV4KEMHook(uniswapV4KEMHook).claimEgTokens(tokens, amounts);
    reward = IERC20(token).balanceOf(address(this)) - reward;
    if (reward > 0) {
      uint256 feeAmount;
      if (rewardFeeX64 > 0) {
        feeAmount +=
          CollectFee.collect(configManager.feeRecipient(), token, reward, rewardFeeX64, CollectFee.FeeType.FARM_REWARD);
      }
      if (gasFeeX64 > 0) {
        feeAmount += CollectFee.collect(configManager.feeRecipient(), token, reward, gasFeeX64, CollectFee.FeeType.GAS);
      }
      reward -= feeAmount;
      if (vaultOwnerAsRecipient && reward > 0) {
        address rewardRecipient = IPrivateVault(address(this)).vaultOwner();
        IERC20(token).safeTransfer(rewardRecipient, reward);
      }
    }
    emit FairFlowRewardClaim(uniswapV4KEMHook, token, amount);
  }
}
