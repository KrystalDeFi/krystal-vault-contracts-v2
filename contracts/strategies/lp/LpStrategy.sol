// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { FixedPoint128 } from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import { FixedPoint96 } from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { IOptimalSwapper } from "../../interfaces/core/IOptimalSwapper.sol";

import "../../interfaces/strategies/ILpStrategy.sol";
import "../../interfaces/core/IConfigManager.sol";

contract LpStrategy is ReentrancyGuard, ILpStrategy {
  using SafeERC20 for IERC20;

  IOptimalSwapper public optimalSwapper;
  IConfigManager public configManager;

  constructor(address _optimalSwapper, address _configManager) {
    require(_optimalSwapper != address(0), ZeroAddress());
    require(_configManager != address(0), ZeroAddress());
    optimalSwapper = IOptimalSwapper(_optimalSwapper);
    configManager = IConfigManager(_configManager);
  }

  /// @notice Get value of the asset in terms of principalToken
  /// @param asset The asset to get the value
  function valueOf(
    AssetLib.Asset memory asset,
    address principalToken
  ) external view returns (uint256 valueInPrincipal) {
    (uint256 amount0, uint256 amount1) = _getAmountsForPosition(INFPM(asset.token), asset.tokenId);
    (uint256 fee0, uint256 fee1) = _getFeesForPosition(INFPM(asset.token), asset.tokenId);
    (, , address token0, address token1, uint24 fee, , , , , , , ) = INFPM(asset.token).positions(asset.tokenId);
    amount0 += fee0;
    amount1 += fee1;

    address pool = IUniswapV3Factory(INFPM(asset.token).factory()).getPool(token0, token1, fee);
    (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    if (token0 == principalToken) {
      priceX96 = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, priceX96);
      valueInPrincipal = amount0 + fee0;
      valueInPrincipal += FullMath.mulDiv(amount1 + fee1, priceX96, FixedPoint96.Q96);
    } else {
      valueInPrincipal = amount1 + fee1;
      valueInPrincipal += FullMath.mulDiv(amount0 + fee0, priceX96, FixedPoint96.Q96);
    }
  }

  /// @notice Converts the asset to another assets
  /// @param assets The assets to convert
  /// @param data The data for the instruction
  /// @return returnAssets The assets that were returned to the msg.sender
  function convert(
    AssetLib.Asset[] memory assets,
    VaultConfig memory vaultConfig,
    bytes calldata data
  ) external nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));

    if (instruction.instructionType == uint8(InstructionType.MintPosition)) {
      MintPositionParams memory params = abi.decode(instruction.params, (MintPositionParams));
      return mintPosition(assets, params, vaultConfig);
    }
    if (instruction.instructionType == uint8(InstructionType.SwapAndMintPosition)) {
      SwapAndMintPositionParams memory params = abi.decode(instruction.params, (SwapAndMintPositionParams));
      return swapAndMintPosition(assets, params, vaultConfig);
    }
    if (instruction.instructionType == uint8(InstructionType.IncreaseLiquidity)) {
      IncreaseLiquidityParams memory params = abi.decode(instruction.params, (IncreaseLiquidityParams));
      return increaseLiquidity(assets, params, vaultConfig);
    }
    if (instruction.instructionType == uint8(InstructionType.SwapAndIncreaseLiquidity)) {
      SwapAndIncreaseLiquidityParams memory params = abi.decode(instruction.params, (SwapAndIncreaseLiquidityParams));
      return swapAndIncreaseLiquidity(assets, params, vaultConfig);
    }
    if (instruction.instructionType == uint8(InstructionType.DecreaseLiquidity)) {
      DecreaseLiquidityParams memory params = abi.decode(instruction.params, (DecreaseLiquidityParams));
      return decreaseLiquidity(assets, params);
    }
    if (instruction.instructionType == uint8(InstructionType.DecreaseLiquidityAndSwap)) {
      DecreaseLiquidityAndSwapParams memory params = abi.decode(instruction.params, (DecreaseLiquidityAndSwapParams));
      return decreaseLiquidityAndSwap(assets, params, vaultConfig);
    }
    revert InvalidInstructionType();
  }

  ///
  function harvest(
    AssetLib.Asset memory asset,
    address tokenOut
  ) external returns (AssetLib.Asset[] memory returnAssets) {
    require(asset.strategy == address(this), InvalidAsset());
    (uint256 principalAmount, uint256 swapAmount) = INFPM(asset.token).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams(asset.tokenId, 0, 0, 0, type(uint256).max)
    );

    (, , address pToken, address swapToken, uint24 fee, , , , , , , ) = INFPM(asset.token).positions(asset.tokenId);
    if (swapToken == tokenOut) {
      (principalAmount, swapAmount) = (swapAmount, principalAmount);
      swapToken = pToken;
    }

    address pool = IUniswapV3Factory(INFPM(asset.token).factory()).getPool(tokenOut, swapToken, fee);
    (uint256 amountOut, uint256 amountInUsed) = _swapToPrinciple(pool, tokenOut, swapToken, swapAmount, 0, "");

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), tokenOut, 0, principalAmount + amountOut);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), swapToken, 0, swapAmount - amountInUsed);
    returnAssets[2] = asset;
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(asset.token).safeTransferFrom(address(this), msg.sender, asset.tokenId);
  }

  function convertFromPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 principalTokenAmount,
    VaultConfig memory vaultConfig
  ) external nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    require(existingAsset.strategy == address(this), InvalidStrategy());

    (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) = INFPM(
      existingAsset.token
    ).positions(existingAsset.tokenId);
    address otherToken = token0 == vaultConfig.principalToken ? token1 : token0;

    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrincipal(
      principalTokenAmount,
      IUniswapV3Factory(INFPM(existingAsset.token).factory()).getPool(token0, token1, fee),
      vaultConfig.principalToken,
      otherToken,
      tickLower,
      tickUpper,
      ""
    );
    IncreaseLiquidityParams memory params = IncreaseLiquidityParams(0, 0);
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](3);
    inputAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
    inputAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
    inputAssets[2] = existingAsset;

    returnAssets = _increaseLiquidity(inputAssets, params);
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  /// @notice Mints a new position
  /// @param assets The assets to mint the position, assets[0] = token0, assets[1] = token1
  /// @param params The parameters for minting the position
  /// @return returnAssets The assets that were returned to the msg.sender
  function mintPosition(
    AssetLib.Asset[] memory assets,
    MintPositionParams memory params,
    VaultConfig memory vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 2, InvalidNumberOfAssets());
    require(
      assets[0].token == vaultConfig.principalToken || assets[1].token == vaultConfig.principalToken,
      InvalidAsset()
    );

    if (vaultConfig.allowDeposit) {
      _validateConfig(
        params.nfpm,
        params.fee,
        params.token0,
        params.token1,
        params.tickLower,
        params.tickUpper,
        vaultConfig
      );
    }

    returnAssets = _mintPosition(assets, params);
    // Transfer assets to msg.sender
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  function swapAndMintPosition(
    AssetLib.Asset[] memory assets,
    SwapAndMintPositionParams memory params,
    VaultConfig memory vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].token == vaultConfig.principalToken, InvalidAsset());
    if (vaultConfig.allowDeposit) {
      _validateConfig(
        params.nfpm,
        params.fee,
        params.token0,
        params.token1,
        params.tickLower,
        params.tickUpper,
        vaultConfig
      );
    }

    address pool = IUniswapV3Factory(params.nfpm.factory()).getPool(params.token0, params.token1, params.fee);
    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrincipal(
      assets[0].amount,
      pool,
      params.token0,
      params.token1,
      params.tickLower,
      params.tickUpper,
      params.swapData
    );

    assets = new AssetLib.Asset[](2);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), params.token0, 0, amount0);
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), params.token1, 0, amount1);
    returnAssets = _mintPosition(
      assets,
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
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  function _mintPosition(
    AssetLib.Asset[] memory assets,
    MintPositionParams memory params
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    (AssetLib.Asset memory token0, AssetLib.Asset memory token1) = assets[0].token < assets[1].token
      ? (assets[0], assets[1])
      : (assets[1], assets[0]);

    IERC20(token0.token).approve(address(params.nfpm), token0.amount);
    IERC20(token1.token).approve(address(params.nfpm), token1.amount);

    (uint256 tokenId, , uint256 amount0, uint256 amount1) = params.nfpm.mint(
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
  /// @return returnAssets The assets that were returned to the msg.sender
  function increaseLiquidity(
    AssetLib.Asset[] memory assets,
    IncreaseLiquidityParams memory params,
    VaultConfig memory vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 3, InvalidNumberOfAssets());
    require(assets[2].strategy == address(this), InvalidAsset());
    require(
      assets[0].token == vaultConfig.principalToken || assets[1].token == vaultConfig.principalToken,
      InvalidAsset()
    );

    returnAssets = _increaseLiquidity(assets, params);
    // Transfer assets to msg.sender
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  function swapAndIncreaseLiquidity(
    AssetLib.Asset[] memory assets,
    SwapAndIncreaseLiquidityParams memory params,
    VaultConfig memory vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 2, InvalidNumberOfAssets());
    require(assets[0].token == vaultConfig.principalToken, InvalidAsset());

    AssetLib.Asset memory lpAsset = assets[1];
    bytes memory swapData = params.swapData;

    (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) = INFPM(lpAsset.token)
      .positions(lpAsset.tokenId);
    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrincipal(
      assets[0].amount,
      IUniswapV3Factory(INFPM(lpAsset.token).factory()).getPool(token0, token1, fee),
      token0,
      token1,
      tickLower,
      tickUpper,
      swapData
    );
    assets = new AssetLib.Asset[](3);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
    assets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
    assets[2] = lpAsset;
    returnAssets = _increaseLiquidity(assets, IncreaseLiquidityParams(params.amount0Min, params.amount1Min));
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  function _increaseLiquidity(
    AssetLib.Asset[] memory assets,
    IncreaseLiquidityParams memory params
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    AssetLib.Asset memory lpAsset = assets[2];
    (AssetLib.Asset memory token0, AssetLib.Asset memory token1) = assets[0].token < assets[1].token
      ? (assets[0], assets[1])
      : (assets[1], assets[0]);

    IERC20(token0.token).approve(address(lpAsset.token), token0.amount);
    IERC20(token1.token).approve(address(lpAsset.token), token1.amount);

    (, uint256 amount0Added, uint256 amount1Added) = INFPM(lpAsset.token).increaseLiquidity(
      INFPM.IncreaseLiquidityParams(
        lpAsset.tokenId,
        token0.amount,
        token1.amount,
        params.amount0Min,
        params.amount1Min,
        block.timestamp
      )
    );

    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = AssetLib.Asset(
      AssetLib.AssetType.ERC20,
      address(0),
      token0.token,
      0,
      token0.amount - amount0Added
    );
    returnAssets[1] = AssetLib.Asset(
      AssetLib.AssetType.ERC20,
      address(0),
      token1.token,
      0,
      token1.amount - amount1Added
    );
    returnAssets[2] = lpAsset;
  }

  /// @notice Decreases the liquidity of the position
  /// @param assets The assets to decrease the liquidity assets[0] = lpAsset
  /// @param params The parameters for decreasing the liquidity
  /// @return returnAssets The assets that were returned to the msg.sender
  function decreaseLiquidity(
    AssetLib.Asset[] memory assets,
    DecreaseLiquidityParams memory params
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == address(this), InvalidAsset());

    returnAssets = _decreaseLiquidity(assets[0], params);
    if (returnAssets[0].amount > 0) {
      IERC20(returnAssets[0].token).safeTransfer(msg.sender, returnAssets[0].amount);
    }
    if (returnAssets[1].amount > 0) {
      IERC20(returnAssets[1].token).safeTransfer(msg.sender, returnAssets[1].amount);
    }
    IERC721(returnAssets[2].token).safeTransferFrom(address(this), msg.sender, returnAssets[2].tokenId);
  }

  function decreaseLiquidityAndSwap(
    AssetLib.Asset[] memory assets,
    DecreaseLiquidityAndSwapParams memory params,
    VaultConfig memory vaultConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == address(this), InvalidAsset());
    address principalToken = vaultConfig.principalToken;

    returnAssets = _decreaseLiquidity(
      assets[0],
      DecreaseLiquidityParams(params.liquidity, params.amount0Min, params.amount1Min)
    );
    (AssetLib.Asset memory principalAsset, AssetLib.Asset memory otherAsset) = returnAssets[0].token == principalToken
      ? (returnAssets[0], returnAssets[1])
      : (returnAssets[1], returnAssets[0]);
    address pool = address(_getPoolForPosition(INFPM(assets[0].token), assets[0].tokenId));
    IERC20(otherAsset.token).approve(address(optimalSwapper), otherAsset.amount);

    (uint256 amountOut, uint256 amountInUsed) = optimalSwapper.poolSwap(
      pool,
      otherAsset.amount,
      otherAsset.token < principalToken,
      params.principalAmountOutMin,
      params.swapData
    );

    otherAsset.amount = otherAsset.amount - amountInUsed;
    principalAsset.amount = principalAsset.amount + amountOut;
    returnAssets = new AssetLib.Asset[](3);
    returnAssets[0] = principalAsset;
    returnAssets[1] = otherAsset;
    returnAssets[2] = assets[0];
    if (principalAsset.amount > 0) {
      IERC20(principalAsset.token).safeTransfer(msg.sender, principalAsset.amount);
    }
    if (otherAsset.amount > 0) IERC20(otherAsset.token).safeTransfer(msg.sender, otherAsset.amount);
    IERC721(assets[0].token).safeTransferFrom(address(this), msg.sender, assets[0].tokenId);
  }

  function _decreaseLiquidity(
    AssetLib.Asset memory lpAsset,
    DecreaseLiquidityParams memory params
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    uint256 amount0Collected;
    uint256 amount1Collected;

    (amount0Collected, amount1Collected) = INFPM(lpAsset.token).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams(
        lpAsset.tokenId,
        params.liquidity,
        params.amount0Min,
        params.amount1Min,
        block.timestamp
      )
    );

    INFPM(lpAsset.token).collect(
      INFPM.CollectParams(lpAsset.tokenId, address(this), type(uint128).max, type(uint128).max)
    );

    (, , address token0, address token1, , , , , , , , ) = INFPM(lpAsset.token).positions(lpAsset.tokenId);

    returnAssets = new AssetLib.Asset[](3);
    // Transfer assets to msg.sender
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0Collected);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1Collected);
    returnAssets[2] = lpAsset;
  }

  /// @notice Swaps the principal token to the other token
  /// @param principalTokenAmount The principal token
  /// @param pool The pool to swap
  /// @param principalToken The principal token
  /// @param otherToken The other token
  /// @param tickLower The lower tick of the position
  /// @param tickUpper The upper tick of the position
  /// @param swapData The swap data
  /// @return amount0 The result amount of pool's token0
  /// @return amount1 The result amount of pool's token1
  function _optimalSwapFromPrincipal(
    uint256 principalTokenAmount,
    address pool,
    address principalToken,
    address otherToken,
    int24 tickLower,
    int24 tickUpper,
    bytes memory swapData
  ) internal returns (uint256 amount0, uint256 amount1) {
    (amount0, amount1) = principalToken < otherToken ? (principalTokenAmount, 0) : (uint256(0), principalTokenAmount);
    IERC20(principalToken).approve(address(optimalSwapper), principalTokenAmount);
    (amount0, amount1) = optimalSwapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams(pool, amount0, amount1, tickLower, tickUpper, swapData)
    );
  }

  function _swapToPrinciple(
    address pool,
    address principalToken,
    address token,
    uint256 amount,
    uint256 amountOutMin,
    bytes memory swapData
  ) internal returns (uint256 amountOut, uint256 amountInUsed) {
    require(token != principalToken, InvalidAsset());

    IERC20(token).approve(address(optimalSwapper), amount);
    (amountOut, amountInUsed) = optimalSwapper.poolSwap(pool, amount, token < principalToken, amountOutMin, swapData);
  }

  /// @notice Gets the underlying assets of the position
  /// @param asset The asset to get the underlying assets
  /// @return underlyingAssets The underlying assets of the position
  function getUnderlyingAssets(
    AssetLib.Asset memory asset
  ) external view returns (AssetLib.Asset[] memory underlyingAssets) {
    require(asset.strategy == address(this), InvalidAsset());

    (uint256 amount0, uint256 amount1) = _getAmountsForPosition(INFPM(asset.token), asset.tokenId);

    (, , address token0, address token1, , , , , , , , ) = INFPM(asset.token).positions(asset.tokenId);
    underlyingAssets = new AssetLib.Asset[](2);
    underlyingAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token0, 0, amount0);
    underlyingAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), token1, 0, amount1);
  }

  /// @dev Gets the pool for the position
  /// @param nfpm The non-fungible position manager
  /// @param tokenId The token id of the position
  /// @return pool The pool for the position
  function _getPoolForPosition(INFPM nfpm, uint256 tokenId) internal view returns (IUniswapV3Pool pool) {
    (, , address token0, address token1, uint24 fee, , , , , , , ) = nfpm.positions(tokenId);
    IUniswapV3Factory factory = IUniswapV3Factory(nfpm.factory());
    pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
  }

  /// @dev Gets the amounts for the position
  /// @param nfpm The non-fungible position manager
  /// @param tokenId The token id of the position
  /// @return amount0 The amount of token0
  /// @return amount1 The amount of token1
  function _getAmountsForPosition(
    INFPM nfpm,
    uint256 tokenId
  ) internal view returns (uint256 amount0, uint256 amount1) {
    (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = nfpm.positions(tokenId);
    IUniswapV3Pool pool = _getPoolForPosition(nfpm, tokenId);
    (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(tickUpper);
    (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      sqrtPriceX96Lower,
      sqrtPriceX96Upper,
      liquidity
    );
  }

  /// @dev Gets the amounts for the pool
  /// @param pool IUniswapV3Pool
  /// @return amount0 The amount of token0
  /// @return amount1 The amount of token1
  function _getAmountsForPool(IUniswapV3Pool pool) internal view returns (uint256 amount0, uint256 amount1) {
    (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    uint128 liquidity = pool.liquidity();
    (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.MIN_SQRT_RATIO,
      TickMath.MAX_SQRT_RATIO,
      liquidity
    );
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
    (, , , , , tickLower, tickUpper, liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128, fee0, fee1) = nfpm
      .positions(tokenId);
    IUniswapV3Pool pool = _getPoolForPosition(nfpm, tokenId);
    (, int24 tick, , , , , ) = pool.slot0();

    (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = _getFeeGrowthInside(
      pool,
      tickLower,
      tickUpper,
      tick
    );

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
  function _getFeeGrowthInside(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    unchecked {
      (, , uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128, , , , ) = pool.ticks(tickLower);
      (, , uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128, , , , ) = pool.ticks(tickUpper);
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

  /// @dev Checks the principal amount in the pool
  /// @param nfpm The non-fungible position manager
  /// @param fee The fee of the pool
  /// @param token0 The token0 of the pool
  /// @param token1 The token1 of the pool
  /// @param tickLower The lower tick of the position
  /// @param tickUpper The upper tick of the position
  /// @param config The configuration of the strategy
  function _validateConfig(
    INFPM nfpm,
    uint24 fee,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    VaultConfig memory config
  ) internal view {
    LpStrategyConfig memory lpConfig = abi.decode(
      configManager.getStrategyConfig(address(this), config.principalToken, config.rangeStrategyType),
      (LpStrategyConfig)
    );

    address pool = IUniswapV3Factory(nfpm.factory()).getPool(token0, token1, fee);
    (uint256 poolAmount0, uint256 poolAmount1) = _getAmountsForPool(IUniswapV3Pool(pool));
    int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

    // Check if the pool is allowed
    require(_isPoolAllowed(config, pool), InvalidPool());

    // Check if the pool amount is greater than the minimum amount principal token
    if (config.principalToken == token0) {
      require(poolAmount0 >= lpConfig.principalTokenAmountMin, InvalidPoolAmountAmountMin());
    } else {
      require(poolAmount1 >= lpConfig.principalTokenAmountMin, InvalidPoolAmountAmountMin());
    }

    // Check if tick width to mint/increase liquidity is greater than the minimum tick width
    if (configManager.isStableToken(token0) && configManager.isStableToken(token1)) {
      require(tickUpper - tickLower >= int24(lpConfig.tickWidthStableMultiplierMin) * tickSpacing, InvalidTickWidth());
    } else {
      require(tickUpper - tickLower >= int24(lpConfig.tickWidthMultiplierMin) * tickSpacing, InvalidTickWidth());
    }
  }

  function _isPoolAllowed(VaultConfig memory config, address pool) internal pure returns (bool) {
    for (uint256 i = 0; i < config.supportedAddresses.length; ) {
      if (config.supportedAddresses[i] == pool) return true;

      unchecked {
        i++;
      }
    }

    return false;
  }

  receive() external payable {}
}
