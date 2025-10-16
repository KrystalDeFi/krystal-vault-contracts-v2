// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IUniswapV4KEMHook } from "../../../common/interfaces/protocols/kyber/IUniswapV4KEMHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrivateConfigManager } from "../../interfaces/core/IPrivateConfigManager.sol";
import { CollectFee } from "../../libraries/CollectFee.sol";

contract KyberFairFlowStrategy {
  address public immutable uniswapV4KEMHook;
  IPrivateConfigManager public immutable configManager;

  error InvalidInputLength();

  event FairFlowRewardClaim(address hook, address token, uint256 amount);

  constructor(address _uniswapV4KEMHook, address _configManager) {
    uniswapV4KEMHook = _uniswapV4KEMHook;
    configManager = IPrivateConfigManager(_configManager);
  }

  function claimFairFlowReward(address token, uint256 amount, uint16 feeBps) external {
    address[] memory tokens = new address[](1);
    tokens[0] = token;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    uint256 reward = IERC20(token).balanceOf(address(this));
    IUniswapV4KEMHook(uniswapV4KEMHook).claimEgTokens(tokens, amounts);
    reward = IERC20(token).balanceOf(address(this)) - reward;
    if (reward > 0 && feeBps > 0) {
      CollectFee.collect(configManager.feeRecipient(), token, reward, feeBps, CollectFee.FARM_REWARD_FEE_TYPE);
    }
    emit FairFlowRewardClaim(uniswapV4KEMHook, token, amount);
  }
}
