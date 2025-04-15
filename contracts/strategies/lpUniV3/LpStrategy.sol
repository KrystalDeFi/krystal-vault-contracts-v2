// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IPancakeV3Pool as IUniswapV3Pool } from "@pancakeswap/v3-core/contracts/interfaces/IPancakeV3Pool.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { FixedPoint128 } from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import { FixedPoint96 } from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import { IOptimalSwapper } from "../../interfaces/core/IOptimalSwapper.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "../../interfaces/strategies/ILpStrategy.sol";
import "../../interfaces/strategies/ILpValidator.sol";

contract LpStrategy is ReentrancyGuard, ILpStrategy, ERC721Holder {
  uint256 constant Q64 = 0x10000000000000000;

  using SafeERC20 for IERC20;

  IOptimalSwapper public optimalSwapper;
  ILpValidator public validator;

  constructor(address _optimalSwapper, address _validator) {
    require(_optimalSwapper != address(0), ZeroAddress());
    require(_validator != address(0), ZeroAddress());
    optimalSwapper = IOptimalSwapper(_optimalSwapper);
    validator = ILpValidator(_validator);
  }

  /// @notice Get value of the asset in terms of principalToken
  /// @param asset The asset to get the value
  /// @param principalToken The principal token
  /// @return valueInPrincipal The value of the asset in terms of principalToken
  function valueOf(AssetLib.Asset calldata asset, address principalToken)
    external
    view
    returns (uint256 valueInPrincipal)
  {
    (uint256 amount0, uint256 amount1) = _getAmountsForPosition(INFPM(asset.token), asset.tokenId);
    (uint256 fee0, uint256 fee1) = _getFeesForPosition(INFPM(asset.token), asset.tokenId);
    (,, address token0, address token1, uint24 fee,,,,,,,) = INFPM(asset.token).positions(asset.tokenId);

    address pool = IUniswapV3Factory(INFPM(asset.token).factory()).getPool(token0, token1, fee);
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    if (token0 == principalToken) {
      priceX96 = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, priceX96);
      valueInPrincipal = amount0 + fee0 + FullMath.mulDiv(amount1 + fee1, priceX96, FixedPoint96.Q96);
    } else {
      valueInPrincipal = amount1 + fee1 + FullMath.mulDiv(amount0 + fee0, priceX96, FixedPoint96.Q96);
    }
  }

  /// @notice Converts the asset to another assets
  /// @param assets The assets to convert
  /// @param vaultConfig The vault configuration
  /// @param feeConfig The fee configuration
  /// @param data The data for the instruction
  /// @return returnAssets The assets that were returned to the msg.sender
  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));
    uint8 instructionType = instruction.instructionType;

    // if (instructionType == uint8(InstructionType.MintPosition)) {
    //   return mintPosition(assets, abi.decode(instruction.params, (MintPositionParams)), vaultConfig);
    // }
    if (instructionType == uint8(InstructionType.SwapAndMintPosition)) {
      return swapAndMintPosition(assets, abi.decode(instruction.params, (SwapAndMintPositionParams)), vaultConfig);
    }
    // if (instructionType == uint8(InstructionType.IncreaseLiquidity)) {
    //   return increaseLiquidity(assets, abi.decode(instruction.params, (IncreaseLiquidityParams)), vaultConfig);
    // }
    if (instructionType == uint8(InstructionType.SwapAndIncreaseLiquidity)) {
      return
        swapAndIncreaseLiquidity(assets, abi.decode(instruction.params, (SwapAndIncreaseLiquidityParams)), vaultConfig);
    }
    if (instructionType == uint8(InstructionType.DecreaseLiquidityAndSwap)) {
      return decreaseLiquidityAndSwap(
        assets, abi.decode(instruction.params, (DecreaseLiquidityAndSwapParams)), vaultConfig, feeConfig
      );
    }
    if (instructionType == uint8(InstructionType.SwapAndRebalancePosition)) {
      return swapAndRebalancePosition(
        assets, abi.decode(instruction.params, (SwapAndRebalancePositionParams)), vaultConfig, feeConfig
      );
    }
    if (instructionType == uint8(InstructionType.SwapAndCompound)) {
      return swapAndCompound(assets, abi.decode(instruction.params, (SwapAndCompoundParams)), feeConfig);
    }

    revert InvalidInstructionType();
  }

  /// @notice Harvest the asset fee
  /// @param asset The asset to harvest
  /// @param tokenOut The token to swap to
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  /// @param vaultConfig The vault configuration
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function harvest(
    AssetLib.Asset calldata asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) external nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    require(asset.strategy == address(this), InvalidAsset());
    returnAssets = _harvest(asset, tokenOut, amountTokenOutMin, vaultConfig, feeConfig);
    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(asset.token).safeTransferFrom(address(this), msg.sender, asset.tokenId);
  }

  /// @dev Harvest the asset fee
  /// @param asset The asset to harvest
  /// @param tokenOut The token to swap to
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  /// @param vaultConfig The vault configuration
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function _harvest(
    AssetLib.Asset calldata asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    (uint256 principalAmount, uint256 swapAmount) = INFPM(asset.token).collect(
      INFPM.CollectParams(asset.tokenId, address(this), type(uint128).max, type(uint128).max)
    );

    (,, address pToken, address swapToken, uint24 fee,,,,,,,) = INFPM(asset.token).positions(asset.tokenId);
    if (swapToken == tokenOut) {
      (principalAmount, swapAmount) = (swapAmount, principalAmount);
      swapToken = pToken;
    }

    uint256 amountOut;
    uint256 amountInUsed;
    address pool = IUniswapV3Factory(INFPM(asset.token).factory()).getPool(tokenOut, swapToken, fee);

    if (swapAmount > 0) {
      (amountOut, amountInUsed) = _swapToPrinciple(
        SwapToPrincipalParams({
          pool: pool,
          principalToken: tokenOut,
          token: swapToken,
          amount: swapAmount,
          amountOutMin: 0,
          swapData: ""
        }),
        vaultConfig.allowDeposit
      );
    }

    // validate principalAmount + amountOut and swapAmount - amountInUsed must be greater than amountTokenOutMin
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    require(
      principalAmount + amountOut + FullMath.mulDiv(swapAmount - amountInUsed, priceX96, FixedPoint96.Q96)
        >= amountTokenOutMin,
      InsufficientAmountOut()
    );

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), tokenOut, 0, principalAmount + amountOut);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), swapToken, 0, swapAmount - amountInUsed);
    returnAssets[2] = asset;

    if (returnAssets[0].amount > 0) returnAssets[0].amount -= _takeFee(tokenOut, returnAssets[0].amount, feeConfig);
    if (returnAssets[1].amount > 0) returnAssets[1].amount -= _takeFee(swapToken, returnAssets[1].amount, feeConfig);
  }

  /// @notice convert the asset from the principal token
  /// @param existingAsset The existing asset to convert
  /// @param principalTokenAmount The amount of principal token
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata vaultConfig
  ) external nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    require(existingAsset.strategy == address(this), InvalidStrategy());

    (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) =
      INFPM(existingAsset.token).positions(existingAsset.tokenId);
    address otherToken = (token0 == vaultConfig.principalToken) ? token1 : token0;

    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrincipal(
      SwapFromPrincipalParams({
        principalTokenAmount: principalTokenAmount,
        pool: IUniswapV3Factory(INFPM(existingAsset.token).factory()).getPool(token0, token1, fee),
        principalToken: vaultConfig.principalToken,
        otherToken: otherToken,
        tickLower: tickLower,
        tickUpper: tickUpper,
        swapData: ""
      }),
      vaultConfig.allowDeposit
    );
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](3);
    inputAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
    inputAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
    inputAssets[2] = existingAsset;

    returnAssets = _increaseLiquidity(inputAssets, IncreaseLiquidityParams(0, 0));
    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  /// @notice convert the asset to the principal token
  /// @param existingAsset The existing asset to convert
  /// @param shares The shares to convert
  /// @param totalSupply The total supply of the shares
  /// @param config The vault configuration
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function convertToPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) external returns (AssetLib.Asset[] memory returnAssets) {
    require(existingAsset.strategy == address(this), InvalidStrategy());
    if (shares > totalSupply) shares = totalSupply;

    INFPM nfpm = INFPM(existingAsset.token);
    uint256 tokenId = existingAsset.tokenId;
    (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) = nfpm.positions(tokenId);

    liquidity = uint128(FullMath.mulDiv(shares, liquidity, totalSupply));
    returnAssets = _decreaseLiquidity(existingAsset, DecreaseLiquidityParams(liquidity, 0, 0), feeConfig);

    (uint256 indexOfPrincipalAsset, uint256 indexOfOtherToken) =
      returnAssets[0].token == config.principalToken ? (0, 1) : (1, 0);
    address pool = IUniswapV3Factory(nfpm.factory()).getPool(token0, token1, fee);

    if (returnAssets[indexOfOtherToken].amount > 0) {
      (uint256 amountOut, uint256 amountInUsed) = _swapToPrinciple(
        SwapToPrincipalParams({
          pool: pool,
          principalToken: returnAssets[indexOfPrincipalAsset].token,
          token: returnAssets[indexOfOtherToken].token,
          amount: returnAssets[indexOfOtherToken].amount,
          amountOutMin: 0,
          swapData: ""
        }),
        config.allowDeposit
      );
      returnAssets[indexOfPrincipalAsset].amount += amountOut;
      returnAssets[indexOfOtherToken].amount -= amountInUsed;
    }

    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(nfpm).safeTransferFrom(address(this), msg.sender, tokenId);
  }

  /// @notice Mints a new position
  /// @param assets The assets to mint the position, assets[0] = token0, assets[1] = token1
  /// @param params The parameters for minting the position
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  // function mintPosition(
  //   AssetLib.Asset[] calldata assets,
  //   MintPositionParams memory params,
  //   VaultConfig calldata vaultConfig
  // ) internal returns (AssetLib.Asset[] memory returnAssets) {
  //   require(assets.length == 2, InvalidNumberOfAssets());
  //   require(
  //     assets[0].token == vaultConfig.principalToken || assets[1].token == vaultConfig.principalToken, InvalidAsset()
  //   );

  //   if (vaultConfig.allowDeposit) {
  //     _validateConfig(
  //       params.nfpm, params.fee, params.token0, params.token1, params.tickLower, params.tickUpper, vaultConfig
  //     );
  //   }

  //   returnAssets = _mintPosition(assets, params);
  //   // Transfer assets to msg.sender
  //   if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
  //   if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
  //   IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  // }

  /// @notice Swaps the principal token to the other token and mints a new position
  /// @param assets The assets to swap and mint, assets[0] = principalToken
  /// @param params The parameters for swapping and minting the position
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function swapAndMintPosition(
    AssetLib.Asset[] calldata assets,
    SwapAndMintPositionParams memory params,
    VaultConfig calldata vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());

    AssetLib.Asset memory principalAsset = assets[0];
    require(principalAsset.token == vaultConfig.principalToken, InvalidAsset());

    if (vaultConfig.allowDeposit) {
      validator.validateConfig(
        params.nfpm, params.fee, params.token0, params.token1, params.tickLower, params.tickUpper, vaultConfig
      );
    }

    address pool = IUniswapV3Factory(params.nfpm.factory()).getPool(params.token0, params.token1, params.fee);
    address principalToken = vaultConfig.principalToken;
    address otherToken = params.token0 == principalToken ? params.token1 : params.token0;
    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrincipal(
      SwapFromPrincipalParams({
        principalTokenAmount: principalAsset.amount,
        pool: pool,
        principalToken: principalToken,
        otherToken: otherToken,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        swapData: params.swapData
      }),
      vaultConfig.allowDeposit
    );

    AssetLib.Asset[] memory mintAssets = new AssetLib.Asset[](2);
    mintAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), params.token0, 0, amount0);
    mintAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), params.token1, 0, amount1);
    returnAssets = _mintPosition(
      vaultConfig,
      mintAssets,
      MintPositionParams({
        nfpm: params.nfpm,
        token0: params.token0,
        token1: params.token1,
        fee: params.fee,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        amount0Min: params.amount0Min,
        amount1Min: params.amount1Min
      })
    );
    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  /// @notice mints a new position
  /// @param vaultConfig The vault configuration
  /// @param assets The assets to mint the position, assets[0] = token0, assets[1] = token1
  /// @param params The parameters for minting the position
  /// @return returnAssets The assets that were returned to the msg.sender
  function _mintPosition(
    VaultConfig calldata vaultConfig,
    AssetLib.Asset[] memory assets,
    MintPositionParams memory params
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    (AssetLib.Asset memory token0, AssetLib.Asset memory token1) =
      assets[0].token < assets[1].token ? (assets[0], assets[1]) : (assets[1], assets[0]);

    IERC20(token0.token).approve(address(params.nfpm), token0.amount);
    IERC20(token1.token).approve(address(params.nfpm), token1.amount);

    if (vaultConfig.allowDeposit) {
      validator.validateObservationCardinality(params.nfpm, params.fee, token0.token, token1.token);
    }

    (uint256 tokenId,, uint256 amount0, uint256 amount1) = params.nfpm.mint(
      INFPM.MintParams(
        token0.token,
        token1.token,
        params.fee,
        params.tickLower,
        params.tickUpper,
        token0.amount,
        token1.amount,
        params.amount0Min,
        params.amount1Min,
        address(this),
        block.timestamp
      )
    );

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0.token, 0, token0.amount - amount0);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1.token, 0, token1.amount - amount1);
    returnAssets[2] = AssetLib.Asset(AssetLib.AssetType.ERC721, address(this), address(params.nfpm), tokenId, 1);
  }

  /// @notice Increases the liquidity of the position
  /// @param assets The assets to increase the liquidity assets[2] = lpAsset
  /// @param params The parameters for increasing the liquidity
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  // function increaseLiquidity(
  //   AssetLib.Asset[] calldata assets,
  //   IncreaseLiquidityParams memory params,
  //   VaultConfig calldata vaultConfig
  // ) internal returns (AssetLib.Asset[] memory returnAssets) {
  //   require(assets.length == 3, InvalidNumberOfAssets());
  //   require(assets[2].strategy == address(this), InvalidAsset());
  //   require(
  //     assets[0].token == vaultConfig.principalToken || assets[1].token == vaultConfig.principalToken, InvalidAsset()
  //   );

  //   returnAssets = _increaseLiquidity(assets, params);
  //   // Transfer assets to msg.sender
  //   if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
  //   if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
  //   IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  // }

  /// @notice Swaps the principal token to the other token and increases the liquidity of the position
  /// @param assets The assets to swap and increase liquidity, assets[2] = lpAsset
  /// @param params The parameters for swapping and increasing the liquidity
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function swapAndIncreaseLiquidity(
    AssetLib.Asset[] calldata assets,
    SwapAndIncreaseLiquidityParams memory params,
    VaultConfig calldata vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 2, InvalidNumberOfAssets());
    require(assets[0].token == vaultConfig.principalToken, InvalidAsset());

    AssetLib.Asset memory asset0 = assets[0];
    AssetLib.Asset memory lpAsset = assets[1];
    INFPM nfpm = INFPM(lpAsset.token);

    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
    {
      // avoid stack too deep
      uint24 fee;
      int24 tickLower;
      int24 tickUpper;
      (,, token0, token1, fee, tickLower, tickUpper,,,,,) = nfpm.positions(lpAsset.tokenId);
      address principalToken = vaultConfig.principalToken;
      address otherToken = token0 == principalToken ? token1 : token0;
      bytes memory swapData = params.swapData;
      (amount0, amount1) = _optimalSwapFromPrincipal(
        SwapFromPrincipalParams({
          principalTokenAmount: asset0.amount,
          pool: IUniswapV3Factory(nfpm.factory()).getPool(token0, token1, fee),
          principalToken: principalToken,
          otherToken: otherToken,
          tickLower: tickLower,
          tickUpper: tickUpper,
          swapData: swapData
        }),
        vaultConfig.allowDeposit
      );
    }

    AssetLib.Asset[] memory incAssets = new AssetLib.Asset[](3);
    incAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
    incAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
    incAssets[2] = lpAsset;

    IncreaseLiquidityParams memory incParams = IncreaseLiquidityParams(params.amount0Min, params.amount1Min);

    returnAssets = _increaseLiquidity(incAssets, incParams);
    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  /// @notice increases the liquidity of the position
  /// @param assets The assets to increase the liquidity assets[2] = lpAsset
  /// @param params The parameters for increasing the liquidity
  /// @return returnAssets The assets that were returned to the msg.sender
  function _increaseLiquidity(AssetLib.Asset[] memory assets, IncreaseLiquidityParams memory params)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    AssetLib.Asset memory lpAsset = assets[2];
    (AssetLib.Asset memory token0, AssetLib.Asset memory token1) =
      assets[0].token < assets[1].token ? (assets[0], assets[1]) : (assets[1], assets[0]);

    IERC20(token0.token).approve(address(lpAsset.token), token0.amount);
    IERC20(token1.token).approve(address(lpAsset.token), token1.amount);

    (, uint256 amount0Added, uint256 amount1Added) = INFPM(lpAsset.token).increaseLiquidity(
      INFPM.IncreaseLiquidityParams(
        lpAsset.tokenId, token0.amount, token1.amount, params.amount0Min, params.amount1Min, block.timestamp
      )
    );

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] =
      AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0.token, 0, token0.amount - amount0Added);
    returnAssets[1] =
      AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1.token, 0, token1.amount - amount1Added);
    returnAssets[2] = lpAsset;
  }

  /// @notice Decreases the liquidity of the position and swaps the other token to the principal token
  /// @param assets The assets to decrease the liquidity assets[0] = lpAsset
  /// @param params The parameters for decreasing the liquidity and swapping
  /// @param vaultConfig The vault configuration
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function decreaseLiquidityAndSwap(
    AssetLib.Asset[] calldata assets,
    DecreaseLiquidityAndSwapParams memory params,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == address(this), InvalidAsset());
    address principalToken = vaultConfig.principalToken;
    AssetLib.Asset memory lpAsset = assets[0];

    returnAssets = _decreaseLiquidity(
      lpAsset, DecreaseLiquidityParams(params.liquidity, params.amount0Min, params.amount1Min), feeConfig
    );

    (AssetLib.Asset memory principalAsset, AssetLib.Asset memory otherAsset) =
      returnAssets[0].token == principalToken ? (returnAssets[0], returnAssets[1]) : (returnAssets[1], returnAssets[0]);

    uint256 amountOut;
    uint256 amountInUsed;
    {
      address pool = address(_getPoolForPosition(INFPM(lpAsset.token), lpAsset.tokenId));
      IERC20(otherAsset.token).approve(address(optimalSwapper), otherAsset.amount);

      bytes memory swapData = params.swapData;
      (amountOut, amountInUsed) =
        optimalSwapper.poolSwap(pool, otherAsset.amount, otherAsset.token < principalToken, 0, swapData);
    }

    otherAsset.amount -= amountInUsed;
    principalAsset.amount += amountOut;

    require(principalAsset.amount >= params.principalAmountOutMin, InsufficientAmountOut());

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = principalAsset;
    returnAssets[1] = otherAsset;
    returnAssets[2] = lpAsset;
    if (principalAsset.amount > 0) IERC20(principalAsset.token).safeTransfer(msg.sender, principalAsset.amount);
    if (otherAsset.amount > 0) IERC20(otherAsset.token).safeTransfer(msg.sender, otherAsset.amount);
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  /// @notice Decreases the liquidity of the position
  /// @param lpAsset The assets to decrease the liquidity assets[0] = lpAsset
  /// @param params The parameters for decreasing the liquidity
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function _decreaseLiquidity(
    AssetLib.Asset memory lpAsset,
    DecreaseLiquidityParams memory params,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    INFPM nfpm = INFPM(lpAsset.token);
    uint256 tokenId = lpAsset.tokenId;

    (,, address token0, address token1,,,,,,,,) = nfpm.positions(tokenId);

    (uint256 amount0Collected, uint256 amount1Collected) =
      nfpm.collect(INFPM.CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max));

    if (amount0Collected > 0) amount0Collected -= _takeFee(token0, amount0Collected, feeConfig);
    if (amount1Collected > 0) amount1Collected -= _takeFee(token1, amount1Collected, feeConfig);

    if (params.liquidity > 0) {
      nfpm.decreaseLiquidity(
        INFPM.DecreaseLiquidityParams(tokenId, params.liquidity, params.amount0Min, params.amount1Min, block.timestamp)
      );

      (uint256 posAmount0, uint256 posAmount1) =
        nfpm.collect(INFPM.CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max));
      amount0Collected += posAmount0;
      amount1Collected += posAmount1;
    }

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0Collected);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1Collected);
    returnAssets[2] = lpAsset;
  }

  /// @notice Swaps the principal token to the other token and rebalances the position
  /// @param assets The assets to swap and rebalance, assets[0] = principalToken, assets[1] = lpAsset
  /// @param params The parameters for swapping and rebalancing the position
  /// @param vaultConfig The vault configuration
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function swapAndRebalancePosition(
    AssetLib.Asset[] calldata assets,
    SwapAndRebalancePositionParams memory params,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == address(this), InvalidAsset());

    AssetLib.Asset calldata asset0 = assets[0];
    IUniswapV3Pool pool = _getPoolForPosition(INFPM(asset0.token), asset0.tokenId);

    if (vaultConfig.allowDeposit) {
      int24 tickLower = params.tickLower;
      int24 tickUpper = params.tickUpper;
      validator.validateTickWidth(pool.token0(), pool.token1(), tickLower, tickUpper, vaultConfig);
    }

    uint256 collected0;
    uint256 collected1;
    if (!params.compoundFee) {
      address principalToken = vaultConfig.principalToken;
      uint256 compoundFeeAmountOutMin = params.compoundFeeAmountOutMin;
      returnAssets = _harvest(asset0, principalToken, compoundFeeAmountOutMin, vaultConfig, feeConfig);
      collected0 = returnAssets[0].amount;
      collected1 = returnAssets[1].amount;
    }
    (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) =
      INFPM(asset0.token).positions(asset0.tokenId);
    {
      uint256 decreasedAmount0Min = params.decreasedAmount0Min;
      uint256 decreasedAmount1Min = params.decreasedAmount1Min;
      returnAssets = _decreaseLiquidity(
        asset0,
        DecreaseLiquidityParams({
          liquidity: liquidity,
          amount0Min: decreasedAmount0Min,
          amount1Min: decreasedAmount1Min
        }),
        feeConfig
      );
    }

    {
      int24 tickLower = params.tickLower;
      int24 tickUpper = params.tickUpper;
      bytes memory data = params.swapData;
      uint256 amount0 = returnAssets[0].amount;
      uint256 amount1 = returnAssets[1].amount;
      IERC20(token0).approve(address(optimalSwapper), amount0);
      IERC20(token1).approve(address(optimalSwapper), amount1);
      (amount0, amount1) = optimalSwapper.optimalSwap(
        IOptimalSwapper.OptimalSwapParams({
          pool: address(pool),
          amount0Desired: amount0,
          amount1Desired: amount1,
          tickLower: tickLower,
          tickUpper: tickUpper,
          data: data
        })
      );

      returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
      returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
    }

    {
      uint256 amount0Min = params.amount0Min;
      uint256 amount1Min = params.amount1Min;
      int24 tickLower = params.tickLower;
      int24 tickUpper = params.tickUpper;
      AssetLib.Asset[] memory tmp = _mintPosition(
        vaultConfig,
        returnAssets,
        MintPositionParams({
          nfpm: INFPM(asset0.token),
          token0: token0,
          token1: token1,
          fee: fee,
          tickLower: tickLower,
          tickUpper: tickUpper,
          amount0Min: amount0Min,
          amount1Min: amount1Min
        })
      );
      returnAssets = new AssetLib.Asset[](4);
      returnAssets[0] = tmp[0];
      returnAssets[1] = tmp[1];
      returnAssets[2] = tmp[2];
      returnAssets[3] = asset0;
    }
    if (!params.compoundFee) {
      returnAssets[0].amount += collected0;
      returnAssets[1].amount += collected1;
    }

    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
    IERC721(returnAssets[3].token).safeTransferFrom(address(this), msg.sender, returnAssets[3].tokenId);
  }

  /// @notice Swaps the principal token to the other token and compounds the position
  /// @param assets The assets to swap and compound, assets[0] = principalToken
  /// @param params The parameters for swapping and compounding the position
  /// @param feeConfig The fee configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function swapAndCompound(
    AssetLib.Asset[] calldata assets,
    SwapAndCompoundParams memory params,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == address(this), InvalidAsset());

    AssetLib.Asset calldata asset0 = assets[0];

    (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) =
      INFPM(asset0.token).positions(asset0.tokenId);

    (uint256 amount0Collected, uint256 amount1Collected) = INFPM(asset0.token).collect(
      INFPM.CollectParams(asset0.tokenId, address(this), type(uint128).max, type(uint128).max)
    );

    if (amount0Collected > 0) amount0Collected -= _takeFee(token0, amount0Collected, feeConfig);
    if (amount1Collected > 0) amount1Collected -= _takeFee(token1, amount1Collected, feeConfig);

    IERC20(token0).approve(address(optimalSwapper), amount0Collected);
    IERC20(token1).approve(address(optimalSwapper), amount1Collected);
    bytes memory swapData = params.swapData;
    (uint256 amount0, uint256 amount1) = optimalSwapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams({
        pool: IUniswapV3Factory(INFPM(asset0.token).factory()).getPool(token0, token1, fee),
        amount0Desired: amount0Collected,
        amount1Desired: amount1Collected,
        tickLower: tickLower,
        tickUpper: tickUpper,
        data: swapData
      })
    );

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
    returnAssets[2] = asset0;

    if (amount0 > 0 || amount1 > 0) {
      uint256 amount0Min = params.amount0Min;
      uint256 amount1Min = params.amount1Min;
      returnAssets = _increaseLiquidity(returnAssets, IncreaseLiquidityParams(amount0Min, amount1Min));
    }

    if (returnAssets[0].amount > 0) IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    if (returnAssets[1].amount > 0) IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  /// @notice Swaps the principal token to the other token
  /// @param params The parameters for swapping the principal token
  /// @return amount0 The amount of token0
  /// @return amount1 The amount of token1
  function _optimalSwapFromPrincipal(SwapFromPrincipalParams memory params, bool checkPriceSanity)
    internal
    returns (uint256 amount0, uint256 amount1)
  {
    if (checkPriceSanity) validator.validatePriceSanity(params.pool);

    (amount0, amount1) = params.principalToken < params.otherToken
      ? (params.principalTokenAmount, 0)
      : (uint256(0), params.principalTokenAmount);
    IERC20(params.principalToken).approve(address(optimalSwapper), params.principalTokenAmount);
    (amount0, amount1) = optimalSwapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams(
        params.pool, amount0, amount1, params.tickLower, params.tickUpper, params.swapData
      )
    );
  }

  /// @notice Swaps the token to the principal token
  /// @param params The parameters for swapping the token
  /// @return amountOut The result amount of principal token
  /// @return amountInUsed The amount of token used
  function _swapToPrinciple(SwapToPrincipalParams memory params, bool checkPriceSanity)
    internal
    returns (uint256 amountOut, uint256 amountInUsed)
  {
    require(params.token != params.principalToken, InvalidAsset());

    if (checkPriceSanity) validator.validatePriceSanity(params.pool);

    IERC20(params.token).approve(address(optimalSwapper), params.amount);
    (amountOut, amountInUsed) = optimalSwapper.poolSwap(
      params.pool, params.amount, params.token < params.principalToken, params.amountOutMin, params.swapData
    );
  }

  /// @notice Revalidate the position
  /// @param asset The asset to revalidate
  /// @param config The vault configuration
  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external view {
    require(asset.strategy == address(this), InvalidAsset());

    (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) =
      INFPM(asset.token).positions(asset.tokenId);

    validator.validateConfig(INFPM(asset.token), fee, token0, token1, tickLower, tickUpper, config);
  }

  /// @dev Gets the pool for the position
  /// @param nfpm The non-fungible position manager
  /// @param tokenId The token id of the position
  /// @return pool The pool for the position
  function _getPoolForPosition(INFPM nfpm, uint256 tokenId) internal view returns (IUniswapV3Pool pool) {
    (,, address token0, address token1, uint24 fee,,,,,,,) = nfpm.positions(tokenId);
    IUniswapV3Factory factory = IUniswapV3Factory(nfpm.factory());
    pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
  }

  /// @dev Gets the amounts for the position
  /// @param nfpm The non-fungible position manager
  /// @param tokenId The token id of the position
  /// @return amount0 The amount of token0
  /// @return amount1 The amount of token1
  function _getAmountsForPosition(INFPM nfpm, uint256 tokenId) internal view returns (uint256 amount0, uint256 amount1) {
    (,,,,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = nfpm.positions(tokenId);
    IUniswapV3Pool pool = _getPoolForPosition(nfpm, tokenId);
    (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
    uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(tickUpper);
    (amount0, amount1) =
      LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, liquidity);
  }

  /// @dev Gets the fees for the position
  /// @param nfpm The non-fungible position manager
  /// @param tokenId The token id of the position
  /// @return fee0 The fee of token0
  /// @return fee1 The fee of token1
  function _getFeesForPosition(INFPM nfpm, uint256 tokenId) internal view returns (uint256 fee0, uint256 fee1) {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    (,,,,, tickLower, tickUpper, liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128, fee0, fee1) =
      nfpm.positions(tokenId);
    IUniswapV3Pool pool = _getPoolForPosition(nfpm, tokenId);
    (, int24 tick,,,,,) = pool.slot0();

    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = _getFeeGrowthInside(pool, tickLower, tickUpper, tick);

    unchecked {
      fee0 += uint128(FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128));
      fee1 += uint128(FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128));
    }
  }

  /// @dev Gets the fee growth inside the position
  /// @param pool The pool for the position
  /// @param tickLower The lower tick of the position
  /// @param tickUpper The upper tick of the position
  /// @param tickCurrent The current tick of the pool
  /// @return feeGrowthInside0X128 The fee growth of token0
  /// @return feeGrowthInside1X128 The fee growth of token1
  function _getFeeGrowthInside(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, int24 tickCurrent)
    internal
    view
    returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
  {
    unchecked {
      (,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,) = pool.ticks(tickLower);
      (,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,) = pool.ticks(tickUpper);
      uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
      uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();

      // calculate fee growth below
      uint256 feeGrowthBelow0X128;
      uint256 feeGrowthBelow1X128;
      if (tickCurrent >= tickLower) {
        feeGrowthBelow0X128 = lowerFeeGrowthOutside0X128;
        feeGrowthBelow1X128 = lowerFeeGrowthOutside1X128;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128;
      }

      // calculate fee growth above
      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (tickCurrent < tickUpper) {
        feeGrowthAbove0X128 = upperFeeGrowthOutside0X128;
        feeGrowthAbove1X128 = upperFeeGrowthOutside1X128;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upperFeeGrowthOutside0X128;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upperFeeGrowthOutside1X128;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }

  /// @dev Takes the fee from the amount
  /// @param token The token to take the fee
  /// @param amount The amount to take the fee
  /// @param feeConfig The fee configuration
  /// @return totalFeeAmount The total fee amount
  function _takeFee(address token, uint256 amount, FeeConfig memory feeConfig)
    internal
    returns (uint256 totalFeeAmount)
  {
    uint256 feeAmount;
    if (feeConfig.platformFeeBasisPoint > 0) {
      feeAmount = amount * feeConfig.platformFeeBasisPoint / 10_000;
      if (feeAmount > 0) {
        totalFeeAmount += feeAmount;
        IERC20(token).safeTransfer(feeConfig.platformFeeRecipient, feeAmount);
        emit FeeCollected(FeeType.PLATFORM, feeConfig.platformFeeRecipient, token, feeAmount);
      }
    }
    if (feeConfig.vaultOwnerFeeBasisPoint > 0) {
      feeAmount = amount * feeConfig.vaultOwnerFeeBasisPoint / 10_000;
      if (feeAmount > 0) {
        totalFeeAmount += feeAmount;
        IERC20(token).safeTransfer(feeConfig.vaultOwner, feeAmount);
        emit FeeCollected(FeeType.OWNER, feeConfig.vaultOwner, token, feeAmount);
      }
    }
    if (feeConfig.gasFeeX64 > 0) {
      feeAmount = FullMath.mulDiv(amount, feeConfig.gasFeeX64, Q64);
      if (feeAmount > 0) {
        totalFeeAmount += feeAmount;
        IERC20(token).safeTransfer(feeConfig.gasFeeRecipient, feeAmount);
        emit FeeCollected(FeeType.GAS, feeConfig.gasFeeRecipient, token, feeAmount);
      }
    }
  }

  /// @notice Fallback function to receive Ether. This is required for the contract to accept ETH transfers.
  receive() external payable { }
}
