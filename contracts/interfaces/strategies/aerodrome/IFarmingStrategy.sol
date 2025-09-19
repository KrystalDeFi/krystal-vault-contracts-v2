// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../IStrategy.sol";
import "../../strategies/aerodrome/IAerodromeLpStrategy.sol";

interface IFarmingStrategy is IStrategy {
  // Farming instruction types
  enum FarmingInstructionType {
    DepositExistingLP, // Deposit existing LP NFT into farming
    CreateAndDepositLP, // Create LP position and deposit into farming
    WithdrawLP, // Withdraw position from farming but keep as LP NFT
    WithdrawLPToPrincipal, // Withdraw position from farming and convert to principal
    RebalanceAndDeposit, // Rebalance LP position and maintain farming
    HarvestFarmingRewards // Harvest farming rewards only

  }

  // Parameter structures
  struct DepositExistingLPParams {
    address gauge;
  }

  struct CreateAndDepositLPParams {
    address gauge;
    IAerodromeLpStrategy.SwapAndMintPositionParams lpParams;
  }

  struct WithdrawLPParams {
    uint256 minPrincipalAmount;
  }

  struct WithdrawLPToPrincipalParams {
    IAerodromeLpStrategy.DecreaseLiquidityAndSwapParams decreaseAndSwapParams;
  }

  struct RebalanceAndDepositParams {
    IAerodromeLpStrategy.SwapAndRebalancePositionParams rebalanceParams;
  }

  struct HarvestFarmingRewardsParams {
    address gauge;
    uint256 tokenId;
    address swapRouter;
    bytes swapData;
    uint256 minAmountOut;
  }

  // Events
  event NFTDeposited(uint256 indexed tokenId, address indexed gauge, address indexed user);
  event NFTWithdrawn(uint256 indexed tokenId, address indexed gauge, address indexed user);
  event FarmingRewardsHarvested(address indexed gauge, address indexed rewardToken, uint256 amount);
  event LPCreatedAndDeposited(uint256 indexed tokenId, address indexed gauge, uint256 liquidity);

  // Errors
  error InvalidFarmingInstructionType();
  error InvalidGauge();
  error InvalidNFT();
  error NFTNotDeposited();
  error NFTAlreadyDeposited();
  error GaugeNotFound();
  error DelegationFailed();
  error UnsupportedRewardToken();
}
