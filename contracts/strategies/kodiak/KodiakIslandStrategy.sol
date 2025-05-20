// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRewardVault } from "../../interfaces/strategies/kodiak/IRewardVault.sol";
import { IKodiakIslandStrategy } from "../../interfaces/strategies/kodiak/IKodiakIslandStrategy.sol";
import { IKodiakIsland, IUniswapV3Pool } from "../../interfaces/strategies/kodiak/IKodiakIsland.sol";
import { AssetLib } from "../../libraries/AssetLib.sol";
import { IOptimalSwapper } from "../../interfaces/core/IOptimalSwapper.sol";
import { ILpFeeTaker } from "../../interfaces/strategies/ILpFeeTaker.sol";
import { ILpValidator } from "../../interfaces/strategies/ILpValidator.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBGT } from "../../interfaces/strategies/kodiak/IBGT.sol";
import { IWETH9 } from "../../interfaces/IWETH9.sol";
import { BgtRedeemer } from "./BgtRedeemer.sol";

contract KodiakIslandStrategy is IKodiakIslandStrategy, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // Constants
  uint256 internal constant Q64 = 0x10000000000000000;
  uint256 internal constant Q96 = 0x1000000000000000000000000;
  uint256 internal constant Q128 = 0x100000000000000000000000000000000;
  uint256 internal constant Q192 = 0x1000000000000000000000000000000000000000000000000;

  // Immutable state variables
  IOptimalSwapper public immutable optimalSwapper;
  ILpFeeTaker public immutable lpFeeTaker;
  address public immutable whitelistRewardVaultFactory;
  IBGT public immutable bgtToken;
  address public immutable wbera;
  BgtRedeemer private immutable bgtRedeemer;
  address private immutable thisAddress;

  // Events
  event KodiakIslandStrategyCompound(
    address indexed vaultAddress, uint256 amount0Collected, uint256 amount1Collected, AssetLib.Asset[] compoundAssets
  );

  constructor(
    address _optimalSwapper,
    address _whitelistRewardVaultFactory,
    address _lpFeeTaker,
    address _bgtToken,
    address _wbera
  ) {
    require(_optimalSwapper != address(0), ZeroAddress());
    require(_whitelistRewardVaultFactory != address(0), ZeroAddress());
    require(_lpFeeTaker != address(0), ZeroAddress());

    optimalSwapper = IOptimalSwapper(_optimalSwapper);
    lpFeeTaker = ILpFeeTaker(_lpFeeTaker);
    whitelistRewardVaultFactory = _whitelistRewardVaultFactory;
    bgtToken = IBGT(_bgtToken);
    wbera = _wbera;
    bgtRedeemer = new BgtRedeemer(wbera);
    thisAddress = address(this);
  }

  function valueOf(AssetLib.Asset calldata asset, address principalToken)
    external
    view
    returns (uint256 valueInPrincipal)
  {
    IRewardVault rewardVault = IRewardVault(asset.token);
    valueInPrincipal = rewardVault.earned(msg.sender);

    IKodiakIsland kodiakIsland = IKodiakIsland(rewardVault.stakeToken());
    (uint256 amount0, uint256 amount1) = kodiakIsland.getUnderlyingBalances();

    // Scale amounts based on the asset's amount relative to total supply
    uint256 totalSupply = kodiakIsland.totalSupply();
    amount0 = FullMath.mulDiv(amount0, asset.amount, totalSupply);
    amount1 = FullMath.mulDiv(amount1, asset.amount, totalSupply);

    // Get token addresses
    IERC20 token0 = kodiakIsland.token0();
    IERC20 token1 = kodiakIsland.token1();

    // Get pool for price calculation
    (uint160 sqrtPriceX96,,,,,,) = kodiakIsland.pool().slot0();
    uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

    // Calculate value in terms of principal token
    if (address(token0) == principalToken) {
      priceX96 = Q192 / priceX96;
      valueInPrincipal += amount0 + FullMath.mulDiv(amount1, priceX96, Q96);
    } else if (address(token1) == principalToken) {
      valueInPrincipal += amount1 + FullMath.mulDiv(amount0, priceX96, Q96);
    } else {
      revert InvalidPrincipalToken();
    }
  }

  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external payable returns (AssetLib.Asset[] memory) {
    require(assets.length > 0, InvalidNumberOfAssets());

    Instruction memory instruction = abi.decode(data, (Instruction));

    if (instruction.instructionType == uint8(InstructionType.SwapAndStake)) {
      return _swapAndStake(assets, config, feeConfig, instruction.params);
    } else if (instruction.instructionType == uint8(InstructionType.WithdrawAndSwap)) {
      return _withdrawAndSwap(assets, config, feeConfig, instruction.params);
    } else {
      revert InvalidInstructionType();
    }
  }

  function _swapAndStake(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata,
    bytes memory params
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].token == config.principalToken, InvalidAsset());

    SwapAndStakeParams memory swapParams = abi.decode(params, (SwapAndStakeParams));
    IRewardVault rewardVault = IRewardVault(swapParams.bgtRewardVault);
    IKodiakIsland kodiakIsland = IKodiakIsland(rewardVault.stakeToken());
    require(rewardVault.factory() == whitelistRewardVaultFactory, InvalidIslandFactory());

    // Get token addresses
    IERC20 token0 = kodiakIsland.token0();
    IERC20 token1 = kodiakIsland.token1();
    require(address(token0) == wbera || address(token1) == wbera, InvalidPrincipalToken());

    // Perform optimal swap
    uint256 principalAmount = assets[0].amount;
    _safeResetAndApprove(IERC20(config.principalToken), address(optimalSwapper), principalAmount);
    (uint256 amount0, uint256 amount1) = optimalSwapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams({
        pool: address(kodiakIsland.pool()),
        amount0Desired: address(token0) == config.principalToken ? principalAmount : 0,
        amount1Desired: address(token1) == config.principalToken ? principalAmount : 0,
        tickLower: kodiakIsland.lowerTick(),
        tickUpper: kodiakIsland.upperTick(),
        data: ""
      })
    );

    // Approve tokens for Kodiak Island
    _safeResetAndApprove(IERC20(token0), address(kodiakIsland), amount0);
    _safeResetAndApprove(IERC20(token1), address(kodiakIsland), amount1);

    (,, uint256 mintAmount) = kodiakIsland.getMintAmounts(amount0, amount1);
    // Mint Kodiak Island LP tokens
    uint256 lpTokenAmount = kodiakIsland.balanceOf(address(this));
    (uint256 amount0Used, uint256 amount1Used,) = kodiakIsland.mint(mintAmount, address(this));
    lpTokenAmount = kodiakIsland.balanceOf(address(this)) - lpTokenAmount;

    _safeResetAndApprove(IERC20(address(kodiakIsland)), address(rewardVault), lpTokenAmount);
    uint256 stakeTokenAmount = IERC20(address(rewardVault)).balanceOf(address(this));
    rewardVault.stake(lpTokenAmount);
    stakeTokenAmount = IERC20(address(rewardVault)).balanceOf(address(this)) - stakeTokenAmount;

    // Prepare return assets
    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(token0), 0, amount0 - amount0Used);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(token1), 0, amount1 - amount1Used);
    returnAssets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, thisAddress, address(rewardVault), 0, stakeTokenAmount);
  }

  function _withdrawAndSwap(
    AssetLib.Asset[] memory assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes memory params
  ) internal returns (AssetLib.Asset[] memory) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == thisAddress, InvalidAsset());

    WithdrawAndSwapParams memory swapParams = abi.decode(params, (WithdrawAndSwapParams));
    IRewardVault rewardVault = IRewardVault(assets[0].token);
    uint256 redeemedBera = _harvestAndTakeFee(rewardVault, feeConfig);

    IKodiakIsland kodiakIsland = IKodiakIsland(rewardVault.stakeToken());

    uint256 burnAmount = kodiakIsland.balanceOf(address(this));
    rewardVault.withdraw(assets[0].amount);
    burnAmount = kodiakIsland.balanceOf(address(this)) - burnAmount;

    // Burn Kodiak Island LP tokens
    (uint256 amount0, uint256 amount1,) = kodiakIsland.burn(burnAmount, address(this));

    // Get token addresses
    IERC20 token0 = kodiakIsland.token0();
    IERC20 token1 = kodiakIsland.token1();

    // Swap tokens to principal token
    if (address(token1) == config.principalToken) {
      _safeResetAndApprove(IERC20(token0), address(optimalSwapper), amount0);
      (uint256 amountOut, uint256 amountInUsed) =
        optimalSwapper.poolSwap(address(kodiakIsland.pool()), amount0, true, 0, "");
      amount1 += amountOut + redeemedBera;
      require(amount1 >= swapParams.minPrincipalAmount, InsufficientAmountOut());

      amount0 -= amountInUsed;
    }
    if (address(token1) != config.principalToken) {
      _safeResetAndApprove(IERC20(token1), address(optimalSwapper), amount1);
      (uint256 amountOut, uint256 amountInUsed) =
        optimalSwapper.poolSwap(address(kodiakIsland.pool()), amount1, false, 0, "");
      amount0 += amountOut + redeemedBera;
      require(amount0 >= swapParams.minPrincipalAmount, InsufficientAmountOut());

      amount1 -= amountInUsed;
    }

    // Prepare return assets
    AssetLib.Asset[] memory returnAssets = new AssetLib.Asset[](2);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(token0), 0, amount0);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(token1), 0, amount1);

    return returnAssets;
  }

  /// @dev some tokens require allowance == 0 to approve new amount
  /// but some tokens does not allow approve amount = 0
  /// we try to set allowance = 0 before approve new amount. if it revert means that
  /// the token not allow to approve 0, which means the following line code will work properly
  function _safeResetAndApprove(IERC20 token, address _spender, uint256 _value) internal {
    if (_value == 0) return;

    /// @dev omitted approve(0) result because it might fail and does not break the flow
    address(token).call(abi.encodeWithSelector(token.approve.selector, _spender, 0));

    /// @dev value for approval after reset must greater than 0
    _safeApprove(token, _spender, _value);
  }

  function _safeApprove(IERC20 token, address _spender, uint256 _value) internal {
    (bool success, bytes memory returnData) =
      address(token).call(abi.encodeWithSelector(token.approve.selector, _spender, _value));
    if (_value == 0) {
      // some token does not allow approve(0) so we skip check for this case
      return;
    }
    require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), ApproveFailed());
  }

  function _takeFee(address token, uint256 amount, FeeConfig calldata feeConfig)
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

  function harvest(AssetLib.Asset calldata asset, address, uint256, VaultConfig calldata, FeeConfig calldata feeConfig)
    external
    payable
    returns (AssetLib.Asset[] memory returnAssets)
  {
    require(asset.strategy == thisAddress, InvalidAssetStrategy());
    IRewardVault rewardVault = IRewardVault(asset.token);
    uint256 redeemedBera = _harvestAndTakeFee(rewardVault, feeConfig);
    returnAssets = new AssetLib.Asset[](1);
    returnAssets[0] = asset;
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(wbera), 0, redeemedBera);
  }

  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata config
  ) external payable returns (AssetLib.Asset[] memory) {
    require(existingAsset.strategy == thisAddress, InvalidAssetStrategy());

    IKodiakIsland kodiakIsland = IKodiakIsland(existingAsset.token);

    // Get token addresses
    IERC20 token0 = kodiakIsland.token0();
    IERC20 token1 = kodiakIsland.token1();

    // Calculate optimal swap amounts
    uint256 amount0;
    uint256 amount1;
    if (address(token0) == config.principalToken) {
      amount0 = principalTokenAmount;
      amount1 = 0;
    } else {
      amount0 = 0;
      amount1 = principalTokenAmount;
    }

    // Perform optimal swap
    _safeResetAndApprove(IERC20(config.principalToken), address(optimalSwapper), principalTokenAmount);
    (amount0, amount1) = optimalSwapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams({
        pool: address(kodiakIsland.pool()),
        amount0Desired: amount0,
        amount1Desired: amount1,
        tickLower: kodiakIsland.lowerTick(),
        tickUpper: kodiakIsland.upperTick(),
        data: ""
      })
    );

    // Approve tokens for Kodiak Island
    _safeResetAndApprove(IERC20(token0), address(kodiakIsland), amount0);
    _safeResetAndApprove(IERC20(token1), address(kodiakIsland), amount1);

    (,, uint256 mintAmount) = kodiakIsland.getMintAmounts(amount0, amount1);
    // Mint Kodiak Island LP tokens
    (uint256 amount0Used, uint256 amount1Used, uint128 liquidityMinted) = kodiakIsland.mint(mintAmount, address(this));

    // Prepare return assets
    AssetLib.Asset[] memory returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(token0), 0, amount0 - amount0Used);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(token1), 0, amount1 - amount1Used);
    returnAssets[2] = AssetLib.Asset(AssetLib.AssetType.ERC20, thisAddress, address(kodiakIsland), 0, liquidityMinted);

    return returnAssets;
  }

  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) external payable returns (AssetLib.Asset[] memory returnAssets) {
    require(existingAsset.strategy == thisAddress, InvalidAssetStrategy());
    if (shares > totalSupply) shares = totalSupply;

    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = existingAsset;

    if (shares < totalSupply) {
      inputAssets[0].amount = FullMath.mulDiv(existingAsset.amount, shares, totalSupply);
      AssetLib.Asset[] memory outputAssets = _withdrawAndSwap(inputAssets, config, feeConfig, "");

      returnAssets = new AssetLib.Asset[](outputAssets.length + 1);
      existingAsset.amount -= inputAssets[0].amount;
      returnAssets[outputAssets.length] = existingAsset;
    }

    return _withdrawAndSwap(inputAssets, config, feeConfig, "");
  }

  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external { }

  function _harvestAndTakeFee(IRewardVault rewardVault, FeeConfig calldata feeConfig)
    internal
    returns (uint256 redeemedBera)
  {
    uint256 rewardAmount = rewardVault.getReward(address(this), address(this));
    bgtRedeemer.setReceiver(address(this));
    redeemedBera = IERC20(wbera).balanceOf(address(this));
    IBGT(rewardVault.rewardToken()).redeem(address(bgtRedeemer), rewardAmount);
    redeemedBera = IERC20(wbera).balanceOf(address(this)) - redeemedBera;
    redeemedBera -= _takeFee(wbera, redeemedBera, feeConfig);
  }

  // Add receive function for ETH
  receive() external payable { }
}
