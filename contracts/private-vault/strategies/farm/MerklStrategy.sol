// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IMerklDistributor } from "../../../common/interfaces/protocols/merkl/IMerklDistributor.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrivateConfigManager } from "../../interfaces/core/IPrivateConfigManager.sol";
import { CollectFee } from "../../libraries/CollectFee.sol";

/**
 * @title MerklStrategy
 * @notice Strategy for handling Merkl rewards for LP positions
 */
contract MerklStrategy {
  address public immutable distributor;
  IPrivateConfigManager public immutable configManager;

  event MerklRewardClaim(address distributor, address token, uint256 amount);

  constructor(address _distributor, address _configManager) {
    distributor = _distributor;
    configManager = IPrivateConfigManager(_configManager);
  }

  function claimMerkleReward(
    address token,
    uint256 amount,
    bytes32[] memory proofs,
    uint64 rewardFeeX64,
    uint64 gasFeeX64
  ) external {
    address[] memory users = new address[](1);
    users[0] = address(this);
    address[] memory tokens = new address[](1);
    tokens[0] = token;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;
    bytes32[][] memory proofsArray = new bytes32[][](1);
    proofsArray[0] = proofs;

    uint256 rewardAmount = IERC20(token).balanceOf(address(this));
    IMerklDistributor(distributor).claim(users, tokens, amounts, proofsArray);
    rewardAmount = IERC20(token).balanceOf(address(this)) - rewardAmount;
    if (rewardAmount > 0) {
      if (rewardFeeX64 > 0) {
        CollectFee.collect(
          configManager.feeRecipient(), token, rewardAmount, rewardFeeX64, CollectFee.FeeType.FARM_REWARD
        );
      }
      if (gasFeeX64 > 0) {
        CollectFee.collect(
          configManager.feeRecipient(), token, rewardAmount, gasFeeX64, CollectFee.FeeType.GAS
        );
      }
    }

    emit MerklRewardClaim(distributor, token, rewardAmount);
  }
}
