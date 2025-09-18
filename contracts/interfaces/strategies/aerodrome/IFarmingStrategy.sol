// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../IStrategy.sol";

interface IFarmingStrategy is IStrategy {
  // Instruction types for farming operations
  enum InstructionType {
    Deposit, // Deposit NFT into farming
    Withdraw, // Withdraw NFT from farming
    Harvest // Harvest rewards only

  }

  // Parameters for deposit instruction
  struct DepositParams {
    address gauge; // Address of the CLGauge to deposit into
    uint256 tokenId; // NFT token ID to deposit
  }

  // Parameters for withdraw instruction
  struct WithdrawParams {
    address gauge; // Address of the CLGauge to withdraw from
    uint256 tokenId; // NFT token ID to withdraw
    bool claimRewards; // Whether to claim rewards during withdrawal
  }

  // Parameters for harvest instruction
  struct HarvestParams {
    address gauge; // Address of the CLGauge to harvest from
    uint256 tokenId; // NFT token ID to harvest rewards for
    address swapRouter; // Router to use for reward swapping
    bytes swapData; // Swap data for reward token conversion
    uint256 minAmountOut; // Minimum amount of principal token expected
  }

  // Events
  event NFTDeposited(uint256 indexed tokenId, address indexed gauge, address indexed user);
  event NFTWithdrawn(uint256 indexed tokenId, address indexed gauge, address indexed user);
  event RewardsHarvested(address indexed gauge, address indexed rewardToken, uint256 amount);
  event RewardSwapped(address indexed rewardToken, address indexed principalToken, uint256 amountIn, uint256 amountOut);

  // Errors
  error InvalidAssetType();
  error InvalidGauge();
  error InvalidNFT();
  error NFTNotOwned();
  error GaugeNotFound();
  error RewardSwapperNotSet();
  error SwapFailed();
  error NotEnoughRewards();
  error UnsupportedRewardToken();

  /**
   * @notice Get the pending rewards for a farmed NFT position
   * @param gauge Address of the CLGauge
   * @param tokenId NFT token ID
   * @return rewardAmount Amount of pending rewards
   */
  function getPendingRewards(address gauge, uint256 tokenId) external view returns (uint256 rewardAmount);

  /**
   * @notice Check if an NFT can be deposited into a specific gauge
   * @param nftContract Address of the NFT contract
   * @param tokenId NFT token ID
   * @param gauge Address of the CLGauge
   * @return canDeposit Whether the NFT can be deposited
   */
  function canDeposit(address nftContract, uint256 tokenId, address gauge) external view returns (bool canDeposit);

  /**
   * @notice Get the gauge address for a farmed NFT
   * @param nftContract Address of the NFT contract
   * @param tokenId NFT token ID
   * @return gauge Address of the gauge where the NFT is deposited (zero if not deposited)
   */
  function getGaugeForNFT(address nftContract, uint256 tokenId) external view returns (address gauge);
}
