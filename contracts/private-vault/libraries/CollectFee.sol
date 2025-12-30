// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IPrivateConfigManager } from "../interfaces/core/IPrivateConfigManager.sol";

library CollectFee {
  enum FeeType {
    PLATFORM,
    OWNER,
    GAS,
    FARM_REWARD
  }

  using SafeERC20 for IERC20;

  uint256 internal constant Q64 = 0x10000000000000000;

  error InvalidRewardFee();
  error FeeRecipientNotSet();

  event FeeCollect(
    address indexed token,
    uint256 feeAmount,
    uint64 rewardFeeX64,
    FeeType feeType,
    address indexed sender,
    address indexed recipient
  );

  function collect(address recipient, address token, uint256 amount, uint64 rewardFeeX64, FeeType feeType)
    internal
    returns (uint256 feeAmount)
  {
    if (amount == 0 || rewardFeeX64 == 0) return 0;
    if (rewardFeeX64 > Q64) revert InvalidRewardFee();
    if (recipient == address(0)) revert FeeRecipientNotSet();

    feeAmount = Math.mulDiv(amount, rewardFeeX64, Q64);
    if (feeAmount == 0) return 0;

    IERC20(token).safeTransfer(recipient, feeAmount);

    emit FeeCollect(token, feeAmount, rewardFeeX64, feeType, msg.sender, recipient);
  }
}
