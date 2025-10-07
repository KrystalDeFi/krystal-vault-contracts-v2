// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../libraries/AssetLib.sol";
import "../../libraries/SafeApprovalLib.sol";
import "../../interfaces/core/IConfigManager.sol";
import "../../interfaces/strategies/IStrategy.sol";
import "../../../common/interfaces/protocols/aerodrome/ICLGauge.sol";
import "../../../common/interfaces/protocols/aerodrome/ICLFactory.sol";
import "../../../common/interfaces/protocols/aerodrome/ICLPool.sol";
import "../../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import "../../interfaces/strategies/aerodrome/IAerodromeLpStrategy.sol";
import "../../interfaces/strategies/aerodrome/IFarmingStrategy.sol";
import { IFeeTaker } from "../../interfaces/strategies/IFeeTaker.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { INonfungiblePositionManager as INFPM } from
  "../../../common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import "./RewardSwapper.sol";

/**
 * @title FarmingStrategy
 * @notice Strategy for farming Aerodrome LP positions using composition with LpStrategy
 * @dev Uses composition to delegate LP operations to LpStrategy while adding farming capabilities
 */
contract FarmingStrategy is IFarmingStrategy, IERC721Receiver, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  uint256 internal constant Q64 = 0x10000000000000000;

  // Core composition components
  address public immutable lpStrategyImplementation;
  IConfigManager public immutable configManager;
  RewardSwapper public immutable rewardSwapper;
  address private immutable thisAddress;

  // Note: No storage state variables - farming state tracked via asset encoding
  // asset.strategy = thisAddress + asset.token = gaugeAddress means position is deposited in farming
  // asset.strategy = lpStrategyImplementation + asset.token = nftContract means regular LP position

  /**
   * @notice Constructor
   * @param _lpStrategyImplementation Address of the LpStrategy implementation for delegatecall
   * @param _configManager Address of the config manager
   * @param _rewardSwapper Address of the reward swapper contract
   */
  constructor(address _lpStrategyImplementation, address _configManager, address _rewardSwapper) {
    require(_lpStrategyImplementation != address(0), ZeroAddress());
    require(_configManager != address(0), ZeroAddress());
    require(_rewardSwapper != address(0), ZeroAddress());

    lpStrategyImplementation = _lpStrategyImplementation;
    configManager = IConfigManager(_configManager);
    rewardSwapper = RewardSwapper(_rewardSwapper);
    thisAddress = address(this);
  }

  /**
   * @notice Calculate the value of a farming position including LP value and pending rewards
   * @param asset The farming asset
   * @param principalToken The principal token to value against
   * @return The total value in principal token terms
   */
  function valueOf(AssetLib.Asset calldata asset, address principalToken) external view override returns (uint256) {
    if (asset.assetType != AssetLib.AssetType.ERC721) return 0;

    address gauge = asset.token;
    AssetLib.Asset memory lpAsset = asset;
    lpAsset.strategy = lpStrategyImplementation;
    lpAsset.token = ICLGauge(asset.token).nft();
    // Get LP position value by delegating to LpStrategy
    uint256 lpValue = IStrategy(lpStrategyImplementation).valueOf(lpAsset, principalToken);

    // Add farming rewards value if position is deposited
    if (gauge != address(0)) {
      uint256 pendingRewards = ICLGauge(gauge).earned(msg.sender, asset.tokenId);
      if (pendingRewards > 0) {
        address rewardToken = ICLGauge(gauge).rewardToken();
        uint256 rewardValue = rewardSwapper.getRewardValue(rewardToken, principalToken, pendingRewards);
        lpValue += rewardValue;
      }
    }

    return lpValue;
  }

  /**
   * @notice Convert assets with farming operations
   * @param assets Input assets
   * @param config Vault configuration
   * @param feeConfig Fee configuration
   * @param data Encoded farming instruction
   * @return returnAssets Output assets
   */
  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external payable override returns (AssetLib.Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));
    uint8 instructionType = instruction.instructionType;

    if (instructionType == uint8(IFarmingStrategy.FarmingInstructionType.DepositExistingLP)) {
      return _depositExistingLP(assets, config);
    } else if (instructionType == uint8(IFarmingStrategy.FarmingInstructionType.CreateAndDepositLP)) {
      return _createAndDepositLP(
        assets, abi.decode(instruction.params, (IFarmingStrategy.CreateAndDepositLPParams)), config, feeConfig
      );
    } else if (instructionType == uint8(IFarmingStrategy.FarmingInstructionType.WithdrawLP)) {
      return _withdrawLP(assets, abi.decode(instruction.params, (IFarmingStrategy.WithdrawLPParams)), config, feeConfig);
    } else if (instructionType == uint8(IFarmingStrategy.FarmingInstructionType.WithdrawLPToPrincipal)) {
      return _withdrawLPToPrincipal(
        assets, abi.decode(instruction.params, (IFarmingStrategy.WithdrawLPToPrincipalParams)), config, feeConfig
      );
    } else if (instructionType == uint8(IFarmingStrategy.FarmingInstructionType.RebalanceAndDeposit)) {
      return _rebalanceAndDeposit(
        assets, abi.decode(instruction.params, (IFarmingStrategy.RebalanceAndDepositParams)), config, feeConfig
      );
    } else if (instructionType == uint8(IFarmingStrategy.FarmingInstructionType.CompoundAndDeposit)) {
      return _compoundAndDeposit(
        assets, abi.decode(instruction.params, (IFarmingStrategy.CompoundAndDepositParams)), config, feeConfig
      );
    } else {
      revert InvalidFarmingInstructionType();
    }
  }

  /**
   * @notice Harvest both LP fees and farming rewards
   * @dev Reverts if LP harvesting fails or minimum output not met
   * @param asset The farming asset
   * @param tokenOut Desired output token
   * @param amountTokenOutMin Minimum output amount
   * @param vaultConfig Vault configuration
   * @param feeConfig Fee configuration
   * @return returnAssets Combined harvest results
   */
  function harvest(
    AssetLib.Asset calldata asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) external payable override returns (AssetLib.Asset[] memory returnAssets) {
    require(asset.assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    // Then harvest farming rewards first
    AssetLib.Asset[] memory farmingHarvestResults = _harvestFarmingRewards(asset, tokenOut, feeConfig);

    // Then withdraw so we can harvest LP fees
    _withdrawPosition(asset);

    AssetLib.Asset memory lpAsset = asset;
    address gauge = asset.token;
    lpAsset.strategy = lpStrategyImplementation;
    lpAsset.token = ICLGauge(gauge).nft();

    // First harvest LP fees by delegating to LpStrategy
    AssetLib.Asset[] memory lpHarvestResults = _lpHarvest(lpAsset, tokenOut, 0, vaultConfig, feeConfig);

    // deposit again
    _depositPosition(lpAsset, gauge);

    // Combine results
    returnAssets = _combineHarvestResults(lpHarvestResults, farmingHarvestResults, asset);

    // Verify minimum output requirement
    uint256 totalOut = 0;
    for (uint256 i = 0; i < returnAssets.length; i++) {
      if (returnAssets[i].token == tokenOut) totalOut += returnAssets[i].amount;
    }
    require(totalOut >= amountTokenOutMin, InsufficientAmountOut());
  }

  /**
   * @notice Convert principal token to farmed LP position
   * @param existingAsset Existing asset (contains farming parameters in strategy field)
   * @param principalTokenAmount Amount of principal token to convert
   * @param config Vault configuration
   * @return returnAssets Array containing the farmed LP position
   */
  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata config
  ) external payable override returns (AssetLib.Asset[] memory returnAssets) {
    require(principalTokenAmount > 0, InvalidParams());

    address gauge = existingAsset.token;

    require(gauge != address(0), InvalidGauge());

    // withdraw from farming
    AssetLib.Asset memory lpAsset = _withdrawPosition(existingAsset);
    // Create zero fee config for internal LP operations
    returnAssets = _lpConvertFromPrincipal(lpAsset, principalTokenAmount, config);

    require(returnAssets.length > 2, DelegationFailed());
    require(returnAssets[2].assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    // Deposit the newly created LP position
    uint256 tokenId = returnAssets[2].tokenId;
    returnAssets[2] = _depositPosition(returnAssets[2], gauge);

    emit LPCreatedAndDeposited(tokenId, gauge, returnAssets[2].amount);
  }

  /**
   * @notice Convert farmed LP position to principal token
   * @param existingAsset The farmed LP asset
   * @param shares Number of shares to convert
   * @param totalSupply Total supply of shares
   * @param config Vault configuration
   * @param feeConfig Fee configuration
   * @return returnAssets Array containing principal token assets
   */
  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) external payable override returns (AssetLib.Asset[] memory returnAssets) {
    require(existingAsset.assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    // Withdraw farming
    AssetLib.Asset memory lpAsset = _withdrawPosition(existingAsset);

    // Delegate to LpStrategy to convert LP to principal
    returnAssets = _lpConvertToPrincipal(lpAsset, shares, totalSupply, config, feeConfig);

    // Deposit again
    address gauge = existingAsset.token;
    returnAssets[2] = _depositPosition(returnAssets[2], gauge);
  }

  /**
   * @notice Validate farming asset
   * @param asset The asset to validate
   * @param config Vault configuration
   */
  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external view override {
    require(asset.assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    // Delegate basic validation to LpStrategy
    _lpRevalidate(asset, config);

    // Additional farming-specific validation could be added here
  }

  // =============================================================================
  // Internal Helper Functions
  // =============================================================================

  /**
   * @notice Check if an asset represents a deposited position
   * @param asset The asset to check
   * @return gauge The gauge address if deposited, address(0) if not deposited
   */
  function _getDepositedGauge(AssetLib.Asset memory asset) internal view returns (address gauge) {
    // If asset.strategy points to FarmingStrategy (thisAddress), position is deposited
    if (asset.strategy == thisAddress) return asset.token; // token field contains gauge address

    return address(0);
  }

  /**
   * @notice Check if an asset represents a deposited position
   * @param asset The asset to check
   * @return isDeposited True if position is deposited in farming
   */
  function _isDeposited(AssetLib.Asset memory asset) internal view returns (bool isDeposited) {
    return asset.strategy == thisAddress;
  }

  /**
   * @notice Check if an asset represents a regular LP position (not deposited)
   * @param asset The asset to check
   * @return isLP True if it's a regular LP position
   */
  function _isRegularLP(AssetLib.Asset memory asset) internal view returns (bool isLP) {
    return asset.strategy == lpStrategyImplementation;
  }

  /**
   * @notice Get the NFT contract address for an asset
   * @param asset The asset to get NFT contract for
   * @return nftContract The NFT contract address
   */
  function _getNFTContract(AssetLib.Asset memory asset) internal view returns (address nftContract) {
    if (_isDeposited(asset)) {
      // For deposited positions, get NFT contract from gauge
      address gauge = asset.token;
      return ICLGauge(gauge).nft();
    } else {
      // For regular LP positions, token field is the NFT contract
      return asset.token;
    }
  }

  // =============================================================================
  // Internal Farming Functions
  // =============================================================================

  /**
   * @notice Get gauge address from existing LP position
   * @param nfpm The NonFungiblePositionManager address
   * @param tokenId The LP position token ID
   * @return gauge The gauge address for this position
   */
  function _getGaugeFromPosition(address nfpm, uint256 tokenId) internal view returns (address gauge) {
    // Get position info to extract token0, token1, and tickSpacing
    (,, address token0, address token1, int24 tickSpacing,,,,,,,) = INFPM(nfpm).positions(tokenId);

    // Get gauge from LP parameters
    return _getGaugeFromLPParams(nfpm, token0, token1, tickSpacing);
  }

  /**
   * @notice Get gauge address from LP creation parameters
   * @param nfpm The NonFungiblePositionManager address
   * @param token0 The first token of the pair
   * @param token1 The second token of the pair
   * @param tickSpacing The tick spacing for the pool
   * @return gauge The gauge address for this pool
   */
  function _getGaugeFromLPParams(address nfpm, address token0, address token1, int24 tickSpacing)
    internal
    view
    returns (address gauge)
  {
    // Get factory from NFPM
    address factory = INFPM(nfpm).factory();

    // Get pool address from factory
    address pool = ICLFactory(factory).getPool(token0, token1, tickSpacing);
    require(pool != address(0), "Pool not found");

    // Get gauge from pool
    gauge = ICLPool(pool).gauge();
    require(gauge != address(0), "Gauge not found");
  }

  /**
   * @notice Validate that reward token is compatible with principal token
   * @param gauge The gauge address to check reward token for
   * @param principalToken The vault's principal token
   */
  function _validateRewardToken(address gauge, address principalToken) internal view {
    address rewardToken = ICLGauge(gauge).rewardToken();

    // Allow if reward token is already the principal token
    if (rewardToken == principalToken) return;

    // Check if there's a valid swap route in RewardSwapper
    require(rewardSwapper.isSwapSupported(rewardToken, principalToken), UnsupportedRewardToken());
  }

  /**
   * @notice Deposit existing LP NFT into farming
   */
  function _depositExistingLP(AssetLib.Asset[] calldata assets, VaultConfig calldata config)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    // Get gauge address automatically from the LP position
    address nftContract = _getNFTContract(assets[0]);
    address gauge = _getGaugeFromPosition(nftContract, assets[0].tokenId);

    // Validate reward token compatibility
    _validateRewardToken(gauge, config.principalToken);

    // Deposit the position
    returnAssets = new AssetLib.Asset[](1);
    returnAssets[0] = _depositPosition(assets[0], gauge);
  }

  /**
   * @notice Create LP position and deposit it into farming
   */
  function _createAndDepositLP(
    AssetLib.Asset[] calldata assets,
    IFarmingStrategy.CreateAndDepositLPParams memory params,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    // Get gauge address automatically from LP parameters
    address gauge = _getGaugeFromLPParams(
      address(params.lpParams.nfpm),
      params.lpParams.token0,
      params.lpParams.token1,
      int24(uint24(params.lpParams.tickSpacing))
    );

    // Validate reward token compatibility
    _validateRewardToken(gauge, config.principalToken);

    // Delegate LP creation to LpStrategy
    bytes memory lpInstructionData = abi.encode(
      Instruction({
        instructionType: uint8(IAerodromeLpStrategy.InstructionType.SwapAndMintPosition),
        params: abi.encode(params.lpParams)
      })
    );

    // Create zero fee config for internal LP operations
    returnAssets = _lpConvert(assets, config, feeConfig, lpInstructionData);

    require(returnAssets.length > 2, DelegationFailed());
    require(returnAssets[2].assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    // Deposit the newly created LP position
    returnAssets[2] = _depositPosition(returnAssets[2], gauge);

    emit LPCreatedAndDeposited(returnAssets[2].tokenId, gauge, returnAssets[2].amount);
  }

  /**
   * @notice Withdraw LP position from farming
   */
  function _withdrawLP(
    AssetLib.Asset[] calldata assets,
    IFarmingStrategy.WithdrawLPParams memory params,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].assetType == AssetLib.AssetType.ERC721, InvalidAsset());

    AssetLib.Asset[] memory farmingHarvestResults = _harvestFarmingRewards(assets[0], config.principalToken, feeConfig);
    AssetLib.Asset memory lpAsset = _withdrawPosition(assets[0]);

    returnAssets = new AssetLib.Asset[](farmingHarvestResults.length + 1);
    for (uint256 i; i < farmingHarvestResults.length; i++) {
      returnAssets[i] = farmingHarvestResults[i];
    }
    returnAssets[farmingHarvestResults.length] = lpAsset;
  }

  /**
   * @notice Withdraw LP position from farming to principal, if position still has liquidity, deposit into farming again
   *
   */
  function _withdrawLPToPrincipal(
    AssetLib.Asset[] calldata assets,
    IFarmingStrategy.WithdrawLPToPrincipalParams memory params,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].assetType == AssetLib.AssetType.ERC721, InvalidAsset());
    address gauge = assets[0].token;

    AssetLib.Asset[] memory farmingHarvestResults = _harvestFarmingRewards(assets[0], config.principalToken, feeConfig);
    AssetLib.Asset memory lpAsset = _withdrawPosition(assets[0]);

    // Delegate LP conversion to LpStrategy
    AssetLib.Asset[] memory lpConvertAssets = new AssetLib.Asset[](1);
    lpConvertAssets[0] = lpAsset;
    lpConvertAssets = _lpConvert(
      lpConvertAssets,
      config,
      feeConfig,
      abi.encode(
        Instruction({
          instructionType: uint8(IAerodromeLpStrategy.InstructionType.DecreaseLiquidityAndSwap),
          params: abi.encode(params.decreaseAndSwapParams)
        })
      )
    );
    returnAssets = new AssetLib.Asset[](farmingHarvestResults.length + lpConvertAssets.length);
    for (uint256 i; i < farmingHarvestResults.length; i++) {
      returnAssets[i] = farmingHarvestResults[i];
    }
    for (uint256 i; i < lpConvertAssets.length; i++) {
      returnAssets[farmingHarvestResults.length + i] = lpConvertAssets[i];
    }
    (,,,,,,, uint128 liquidity,,,,) = INFPM(lpConvertAssets[2].token).positions(lpConvertAssets[2].tokenId);
    if (liquidity > 0) returnAssets[returnAssets.length - 1] = _depositPosition(lpConvertAssets[2], gauge);
  }

  /**
   * @notice Rebalance LP position while maintaining farming deposit
   */
  function _rebalanceAndDeposit(
    AssetLib.Asset[] calldata assets,
    IFarmingStrategy.RebalanceAndDepositParams memory params,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].assetType == AssetLib.AssetType.ERC721, InvalidAsset());
    address gauge = assets[0].token;
    // Harvest farming rewards first

    AssetLib.Asset[] memory farmingHarvestResults = _harvestFarmingRewards(assets[0], config.principalToken, feeConfig);
    // Withdraw temporarily
    AssetLib.Asset memory lpAsset = _withdrawPosition(assets[0]);

    AssetLib.Asset[] memory rebalanceAssets = new AssetLib.Asset[](1);
    rebalanceAssets[0] = lpAsset;
    // Delegate rebalancing to LpStrategy
    bytes memory rebalanceData = abi.encode(
      Instruction({
        instructionType: uint8(IAerodromeLpStrategy.InstructionType.SwapAndRebalancePosition),
        params: abi.encode(params.rebalanceParams)
      })
    );
    rebalanceAssets = _lpConvert(rebalanceAssets, config, feeConfig, rebalanceData);

    // Re-deposit the rebalanced position
    require(rebalanceAssets.length > 2 && rebalanceAssets[2].assetType == AssetLib.AssetType.ERC721, InvalidAsset());
    rebalanceAssets[2] = _depositPosition(rebalanceAssets[2], gauge);
    // combine with farming harvest results

    returnAssets = new AssetLib.Asset[](farmingHarvestResults.length + rebalanceAssets.length);
    for (uint256 i; i < farmingHarvestResults.length; i++) {
      returnAssets[i] = farmingHarvestResults[i];
    }
    for (uint256 i; i < rebalanceAssets.length; i++) {
      returnAssets[farmingHarvestResults.length + i] = rebalanceAssets[i];
    }
  }

  /**
   * @notice Compound LP Position and deposit
   */
  function _compoundAndDeposit(
    AssetLib.Asset[] calldata assets,
    IFarmingStrategy.CompoundAndDepositParams memory params,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].assetType == AssetLib.AssetType.ERC721, InvalidAsset());
    address gauge = assets[0].token;
    // Harvest farming rewards first

    AssetLib.Asset[] memory farmingHarvestResults = _harvestFarmingRewards(assets[0], config.principalToken, feeConfig);
    // Withdraw temporarily
    AssetLib.Asset memory lpAsset = _withdrawPosition(assets[0]);

    AssetLib.Asset[] memory compoundAssets = new AssetLib.Asset[](1);
    compoundAssets[0] = lpAsset;
    // Delegate compound to LpStrategy
    bytes memory compoundData = abi.encode(
      Instruction({
        instructionType: uint8(IAerodromeLpStrategy.InstructionType.SwapAndCompound),
        params: abi.encode(params.swapAndCompoundParams)
      })
    );
    compoundAssets = _lpConvert(compoundAssets, config, feeConfig, compoundData);

    // Re-deposit the rebalanced position
    require(compoundAssets.length > 2 && compoundAssets[2].assetType == AssetLib.AssetType.ERC721, InvalidAsset());
    compoundAssets[2] = _depositPosition(compoundAssets[2], gauge);
    // combine with farming harvest results

    returnAssets = new AssetLib.Asset[](farmingHarvestResults.length + compoundAssets.length);
    for (uint256 i; i < farmingHarvestResults.length; i++) {
      returnAssets[i] = farmingHarvestResults[i];
    }
    for (uint256 i; i < compoundAssets.length; i++) {
      returnAssets[farmingHarvestResults.length + i] = compoundAssets[i];
    }
  }

  /**
   * @notice Deposit a position into the specified gauge
   */
  function _depositPosition(AssetLib.Asset memory lpAsset, address gauge)
    internal
    returns (AssetLib.Asset memory farmingAsset)
  {
    address nftContract = lpAsset.token;
    require(ICLGauge(gauge).nft() == nftContract, InvalidNFT());

    // Approve and deposit NFT into gauge
    IERC721(nftContract).approve(gauge, lpAsset.tokenId);
    ICLGauge(gauge).deposit(lpAsset.tokenId);

    farmingAsset = lpAsset;
    farmingAsset.strategy = thisAddress;
    farmingAsset.token = gauge;

    // Note: State tracking is now handled in asset.strategy field when assets are returned
    emit AerodromeStaked(nftContract, lpAsset.tokenId, gauge, msg.sender);
  }

  /**
   * @notice Withdraw a position from the specified gauge
   */
  function _withdrawPosition(AssetLib.Asset memory farmingAsset) internal returns (AssetLib.Asset memory lpAsset) {
    // Withdraw NFT from gauge (this automatically claims rewards if any)
    ICLGauge(farmingAsset.token).withdraw(farmingAsset.tokenId);
    lpAsset = AssetLib.Asset({
      assetType: farmingAsset.assetType,
      strategy: lpStrategyImplementation,
      token: ICLGauge(farmingAsset.token).nft(),
      tokenId: farmingAsset.tokenId,
      amount: farmingAsset.amount
    });

    // Note: State tracking is now handled in asset.strategy field when assets are returned
    emit AerodromeUnstaked(lpAsset.token, farmingAsset.tokenId, farmingAsset.token, msg.sender);
  }

  /**
   * @notice Harvest farming rewards from a specific gauge
   */
  function _harvestFarmingRewards(AssetLib.Asset calldata asset, address tokenOut, FeeConfig calldata feeConfig)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    address rewardToken = ICLGauge(asset.token).rewardToken();
    uint256 rewardBalanceBefore = IERC20(rewardToken).balanceOf(address(this));
    // Claim rewards
    ICLGauge(asset.token).getReward(asset.tokenId);

    uint256 rewardBalance = IERC20(rewardToken).balanceOf(address(this)) - rewardBalanceBefore;
    uint256 principalAmount;

    // Process rewards (swap if needed or take fees)
    if (rewardToken == tokenOut) {
      uint256 amountAfterFee = rewardBalance - _takeFees(rewardToken, rewardBalance, feeConfig);
      returnAssets = new AssetLib.Asset[](1);
      returnAssets[0] = AssetLib.Asset({
        assetType: AssetLib.AssetType.ERC20,
        strategy: address(0),
        token: rewardToken,
        tokenId: 0,
        amount: amountAfterFee
      });
      principalAmount = amountAfterFee;
    } else {
      // Swap reward token to desired output token via RewardSwapper
      uint256 amountOut = _swapRewardToken(rewardToken, tokenOut, rewardBalance);
      uint256 amountLeft = IERC20(rewardToken).balanceOf(address(this)) - rewardBalanceBefore;
      // Successfully swapped to desired token
      if (amountOut > 0) amountOut = amountOut - _takeFees(tokenOut, amountOut, feeConfig);
      returnAssets = new AssetLib.Asset[](2);
      returnAssets[0] = AssetLib.Asset({
        assetType: AssetLib.AssetType.ERC20,
        strategy: address(0),
        token: tokenOut,
        tokenId: 0,
        amount: amountOut
      });
      principalAmount = amountOut;
      returnAssets[1] = AssetLib.Asset({
        assetType: AssetLib.AssetType.ERC20,
        strategy: address(0),
        token: rewardToken,
        tokenId: 0,
        amount: amountLeft
      });
      if (tokenOut > rewardToken) (returnAssets[0], returnAssets[1]) = (returnAssets[1], returnAssets[0]);
    }

    emit FarmingRewardsHarvested(asset.token, rewardToken, rewardBalance, tokenOut, principalAmount);
  }

  /**
   * @notice Combine LP and farming harvest results
   */
  function _combineHarvestResults(
    AssetLib.Asset[] memory lpResults,
    AssetLib.Asset[] memory farmingResults,
    AssetLib.Asset memory farmingAsset
  ) internal pure returns (AssetLib.Asset[] memory combined) {
    // ignore the LP asset in lpResults, as it was farming in farmingResults
    combined = new AssetLib.Asset[](lpResults.length + farmingResults.length);
    combined[0] = lpResults[0];
    combined[1] = lpResults[1];
    uint256 lpResultLength = lpResults.length - 1;

    for (uint256 i = 0; i < farmingResults.length; i++) {
      combined[lpResultLength + i] = farmingResults[i];
    }
    combined[lpResultLength + farmingResults.length] = farmingAsset;
  }

  /**
   * @notice Swap reward token to desired output token
   * @dev Reverts if reward token is not supported or swap fails
   * @param rewardToken The reward token to swap from
   * @param tokenOut The desired output token
   * @param amount The amount of reward token to swap
   * @return amountOut The amount of output token received
   */
  function _swapRewardToken(address rewardToken, address tokenOut, uint256 amount) internal returns (uint256 amountOut) {
    if (rewardToken == tokenOut || amount == 0) return amount;

    require(rewardSwapper.supportedRewardTokens(rewardToken), UnsupportedRewardToken());

    // Approve RewardSwapper to spend reward tokens using safe approve with fallback pattern
    IERC20(rewardToken).safeResetAndApprove(address(rewardSwapper), amount);

    // Execute swap
    amountOut = rewardSwapper.swapRewardToPrincipal(
      rewardToken,
      tokenOut,
      amount,
      0, // No minimum for internal swapping
      "" // Empty swap data for now
    );
  }

  /**
   * @notice Take fees from harvested rewards
   */
  function _takeFees(address token, uint256 amount, FeeConfig calldata feeConfig)
    internal
    returns (uint256 totalFeeAmount)
  {
    uint256 feeAmount;

    if (feeConfig.vaultOwnerFeeBasisPoint > 0) {
      feeAmount = amount * feeConfig.vaultOwnerFeeBasisPoint / 10_000;
      if (feeAmount > 0) {
        totalFeeAmount += feeAmount;
        IERC20(token).safeTransfer(feeConfig.vaultOwner, feeAmount);
        emit FeeCollected(address(this), FeeType.OWNER, feeConfig.vaultOwner, token, feeAmount);
      }
    }
    if (feeConfig.platformFeeBasisPoint > 0) {
      feeAmount = amount * feeConfig.platformFeeBasisPoint / 10_000;
      if (feeAmount > 0) {
        totalFeeAmount += feeAmount;
        IERC20(token).safeTransfer(feeConfig.platformFeeRecipient, feeAmount);
        emit FeeCollected(address(this), FeeType.PLATFORM, feeConfig.platformFeeRecipient, token, feeAmount);
      }
    }
    if (feeConfig.gasFeeX64 > 0) {
      feeAmount = FullMath.mulDiv(amount, feeConfig.gasFeeX64, Q64);
      if (feeAmount > 0) {
        totalFeeAmount += feeAmount;
        IERC20(token).safeTransfer(feeConfig.gasFeeRecipient, feeAmount);
        emit FeeCollected(address(this), FeeType.GAS, feeConfig.gasFeeRecipient, token, feeAmount);
      }
    }
  }

  // =============================================================================
  // DelegateCall Helper Functions
  // =============================================================================

  /**
   * @notice Generic delegatecall helper for LpStrategy interactions
   * @param callData The encoded function call data
   * @return result The returned data from the delegatecall
   */
  function _delegateToLpStrategy(bytes memory callData) internal returns (bytes memory result) {
    (bool success, bytes memory returnData) = lpStrategyImplementation.delegatecall(callData);

    if (!success) {
      // Forward the revert reason if available
      if (returnData.length > 0) {
        assembly {
          let returnDataSize := mload(returnData)
          revert(add(32, returnData), returnDataSize)
        }
      } else {
        revert DelegationFailed();
      }
    }

    return returnData;
  }

  /**
   * @notice Delegatecall to LpStrategy.convert()
   * @param assets Input assets
   * @param config Vault configuration
   * @param feeConfig Fee configuration
   * @param data Instruction data
   * @return returnAssets Output assets
   */
  function _lpConvert(
    AssetLib.Asset[] memory assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes memory data
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    bytes memory callData = abi.encodeWithSelector(IStrategy.convert.selector, assets, config, feeConfig, data);

    bytes memory result = _delegateToLpStrategy(callData);
    returnAssets = abi.decode(result, (AssetLib.Asset[]));
  }

  /**
   * @notice Delegatecall to LpStrategy.harvest()
   * @param asset The asset to harvest
   * @param tokenOut Desired output token
   * @param amountTokenOutMin Minimum output amount
   * @param vaultConfig Vault configuration
   * @param feeConfig Fee configuration
   * @return returnAssets Harvest results
   */
  function _lpHarvest(
    AssetLib.Asset memory asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    bytes memory callData =
      abi.encodeWithSelector(IStrategy.harvest.selector, asset, tokenOut, amountTokenOutMin, vaultConfig, feeConfig);

    bytes memory result = _delegateToLpStrategy(callData);
    returnAssets = abi.decode(result, (AssetLib.Asset[]));
  }

  /**
   * @notice Delegatecall to LpStrategy.convertToPrincipal()
   * @param existingAsset Existing asset
   * @param shares Number of shares
   * @param totalSupply Total supply
   * @param config Vault configuration
   * @param feeConfig Fee configuration
   * @return returnAssets Conversion results
   */
  function _lpConvertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    bytes memory callData = abi.encodeWithSelector(
      IStrategy.convertToPrincipal.selector, existingAsset, shares, totalSupply, config, feeConfig
    );

    bytes memory result = _delegateToLpStrategy(callData);
    returnAssets = abi.decode(result, (AssetLib.Asset[]));
  }

  function _lpConvertFromPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    bytes memory callData =
      abi.encodeWithSelector(IStrategy.convertFromPrincipal.selector, existingAsset, principalTokenAmount, vaultConfig);

    bytes memory result = _delegateToLpStrategy(callData);
    returnAssets = abi.decode(result, (AssetLib.Asset[]));
  }

  /**
   * @notice Delegatecall to LpStrategy.revalidate()
   * @param asset Asset to validate
   * @param config Vault configuration
   */
  function _lpRevalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) internal view {
    bytes memory callData = abi.encodeWithSelector(IStrategy.revalidate.selector, asset, config);

    (bool success,) = lpStrategyImplementation.staticcall(callData);
    require(success, DelegationFailed());
  }

  /**
   * @notice Handle receiving NFTs
   */
  function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    external
    pure
    override
    returns (bytes4)
  {
    return IERC721Receiver.onERC721Received.selector;
  }

  /**
   * @notice Receive ETH
   */
  receive() external payable { }
}
