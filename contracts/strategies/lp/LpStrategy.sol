// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { FixedPoint128 } from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { IOptimalSwapper } from "../../interfaces/core/IOptimalSwapper.sol";

import "../../interfaces/strategies/ILpStrategy.sol";

contract LpStrategy is ReentrancyGuardUpgradeable, ILpStrategy {
  using SafeERC20 for IERC20;

  address public principleToken;
  IOptimalSwapper public optimalSwapper;

  constructor(address _principleToken, address _optimalSwapper) {
    __ReentrancyGuard_init();

    principleToken = _principleToken;
    optimalSwapper = IOptimalSwapper(_optimalSwapper);
  }

  /// @notice Deposits the asset to the strategy
  /// @param asset The asset to be calculated
  function valueOf(Asset memory asset) external view returns (Asset[] memory assets) {
    (uint256 amount0, uint256 amount1) = _getAmountsForPosition(INFPM(asset.token), asset.tokenId);
    (uint256 fee0, uint256 fee1) = _getFeesForPosition(INFPM(asset.token), asset.tokenId);
    (, , address token0, address token1, , , , , , , , ) = INFPM(asset.token).positions(asset.tokenId);

    assets = new Asset[](2);

    assets[0] = Asset(AssetType.ERC20, address(0), token0, 0, fee0 + amount0);
    assets[1] = Asset(AssetType.ERC20, address(0), token1, 0, fee1 + amount1);
  }

  /// @notice Converts the asset to another assets
  /// @param assets The assets to convert
  /// @param data The data for the instruction
  /// @return returnAssets The assets that were returned to the msg.sender
  function convert(
    Asset[] memory assets,
    bytes calldata data
  ) external nonReentrant returns (Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));

    if (instruction.instructionType == uint8(InstructionType.MintPosition)) {
      MintPositionParams memory params = abi.decode(instruction.params, (MintPositionParams));
      return mintPosition(assets, params);
    }
    if (instruction.instructionType == uint8(InstructionType.SwapAndMintPosition)) {
      SwapAndMintPositionParams memory params = abi.decode(instruction.params, (SwapAndMintPositionParams));
      return swapAndMintPosition(assets, params);
    }
    if (instruction.instructionType == uint8(InstructionType.IncreaseLiquidity)) {
      require(assets.length == 3, InvalidNumberOfAssets());

      IncreaseLiquidityParams memory params = abi.decode(instruction.params, (IncreaseLiquidityParams));
      return increaseLiquidity(assets, params);
    }
    if (instruction.instructionType == uint8(InstructionType.SwapAndIncreaseLiquidity)) {
      require(assets.length == 2, InvalidNumberOfAssets());

      SwapAndIncreaseLiquidityParams memory params = abi.decode(instruction.params, (SwapAndIncreaseLiquidityParams));
      return swapAndIncreaseLiquidity(assets, params);
    }
    if (instruction.instructionType == uint8(InstructionType.DecreaseLiquidity)) {
      require(assets.length == 1, InvalidNumberOfAssets());

      DecreaseLiquidityParams memory params = abi.decode(instruction.params, (DecreaseLiquidityParams));
      return decreaseLiquidity(assets, params);
    }
    if (instruction.instructionType == uint8(InstructionType.DecreaseLiquidityAndSwap)) {
      require(assets.length == 1, InvalidNumberOfAssets());

      DecreaseLiquidityAndSwapParams memory params = abi.decode(instruction.params, (DecreaseLiquidityAndSwapParams));
      return decreaseLiquidityAndSwap(assets, params);
    }
    revert InvalidInstructionType();
  }

  function harvest(Asset memory asset) external returns (Asset[] memory returnAssets) {
    require(asset.strategy == address(this), InvalidAsset());
    (uint256 amount0, uint256 amount1) = INFPM(asset.token).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams(asset.tokenId, 0, 0, 0, type(uint256).max)
    );

    (, , address token0, address token1, , , , , , , , ) = INFPM(asset.token).positions(asset.tokenId);
    returnAssets = new Asset[](3);
    returnAssets[0] = Asset(AssetType.ERC20, address(0), token0, 0, amount0);
    returnAssets[1] = Asset(AssetType.ERC20, address(0), token1, 0, amount1);
    returnAssets[2] = asset;
    if (amount0 > 0) IERC20(token0).safeTransfer(msg.sender, amount0);
    if (amount1 > 0) IERC20(token1).safeTransfer(msg.sender, amount1);
    IERC721(asset.token).safeTransferFrom(address(this), msg.sender, asset.tokenId);
  }

  function convertIntoExisting(
    Asset memory existingAsset,
    Asset[] memory assets
  ) external nonReentrant returns (Asset[] memory returnAssets) {
    require(existingAsset.strategy == address(this), InvalidStrategy());
    require(assets.length == 2, InvalidNumberOfAssets());
    IncreaseLiquidityParams memory params = IncreaseLiquidityParams(0, 0);
    Asset[] memory inputAssets = new Asset[](3);
    inputAssets[0] = assets[0];
    inputAssets[1] = assets[1];
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
    Asset[] memory assets,
    MintPositionParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 2, InvalidNumberOfAssets());
    require(assets[0].token == principleToken || assets[1].token == principleToken, InvalidAsset());

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
    Asset[] memory assets,
    SwapAndMintPositionParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].token == principleToken, InvalidAsset());

    address pool = IUniswapV3Factory(params.nfpm.factory()).getPool(params.token0, params.token1, params.fee);
    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrinciple(
      assets[0].amount,
      pool,
      params.token0,
      params.token1,
      params.tickLower,
      params.tickUpper,
      params.swapData
    );

    assets = new Asset[](2);
    assets[0] = Asset(AssetType.ERC20, address(0), params.token0, 0, amount0);
    assets[1] = Asset(AssetType.ERC20, address(0), params.token1, 0, amount1);
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
    Asset[] memory assets,
    MintPositionParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    (Asset memory token0, Asset memory token1) = assets[0].token < assets[1].token
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

    returnAssets = new Asset[](3);
    returnAssets[0] = Asset(AssetType.ERC20, address(0), token0.token, 0, token0.amount - amount0);
    returnAssets[1] = Asset(AssetType.ERC20, address(0), token1.token, 0, token1.amount - amount1);
    returnAssets[2] = Asset(AssetType.ERC721, address(this), address(params.nfpm), tokenId, 1);
  }

  /// @notice Increases the liquidity of the position
  /// @param assets The assets to increase the liquidity assets[2] = lpAsset
  /// @param params The parameters for increasing the liquidity
  /// @return returnAssets The assets that were returned to the msg.sender
  function increaseLiquidity(
    Asset[] memory assets,
    IncreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 3, InvalidNumberOfAssets());

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
    Asset[] memory assets,
    SwapAndIncreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 2, InvalidNumberOfAssets());
    require(assets[0].token == principleToken, InvalidAsset());

    Asset memory lpAsset = assets[1];
    bytes memory swapData = params.swapData;

    (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) = INFPM(lpAsset.token)
      .positions(lpAsset.tokenId);
    (uint256 amount0, uint256 amount1) = _optimalSwapFromPrinciple(
      assets[0].amount,
      IUniswapV3Factory(INFPM(lpAsset.token).factory()).getPool(token0, token1, fee),
      token0,
      token1,
      tickLower,
      tickUpper,
      swapData
    );
    assets = new Asset[](3);
    assets[0] = Asset(AssetType.ERC20, address(0), token0, 0, amount0);
    assets[1] = Asset(AssetType.ERC20, address(0), token1, 0, amount1);
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
    Asset[] memory assets,
    IncreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    Asset memory lpAsset = assets[2];
    (Asset memory token0, Asset memory token1) = assets[0].token < assets[1].token
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

    returnAssets = new Asset[](3);
    returnAssets[0] = Asset(AssetType.ERC20, address(0), token0.token, 0, token0.amount - amount0Added);
    returnAssets[1] = Asset(AssetType.ERC20, address(0), token1.token, 0, token1.amount - amount1Added);
    returnAssets[2] = lpAsset;
  }

  /// @notice Decreases the liquidity of the position
  /// @param assets The assets to decrease the liquidity assets[0] = lpAsset
  /// @param params The parameters for decreasing the liquidity
  /// @return returnAssets The assets that were returned to the msg.sender
  function decreaseLiquidity(
    Asset[] memory assets,
    DecreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
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
    Asset[] memory assets,
    DecreaseLiquidityAndSwapParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(assets[0].strategy == address(this), InvalidAsset());

    returnAssets = _decreaseLiquidity(
      assets[0],
      DecreaseLiquidityParams(params.liquidity, params.amount0Min, params.amount1Min)
    );
    (Asset memory principleAsset, Asset memory otherAsset) = returnAssets[0].token == principleToken
      ? (returnAssets[0], returnAssets[1])
      : (returnAssets[1], returnAssets[0]);
    address pool = address(_getPoolForPosition(INFPM(assets[0].token), assets[0].tokenId));
    IERC20(otherAsset.token).approve(address(optimalSwapper), otherAsset.amount);

    (uint256 amountOut, uint256 amountInUsed) = optimalSwapper.poolSwap(
      pool,
      otherAsset.amount,
      otherAsset.token < principleToken,
      params.principleAmountOutMin,
      params.swapData
    );

    otherAsset.amount = otherAsset.amount - amountInUsed;
    principleAsset.amount = principleAsset.amount + amountOut;
    returnAssets = new Asset[](3);
    returnAssets[0] = principleAsset;
    returnAssets[1] = otherAsset;
    returnAssets[2] = assets[0];
    if (principleAsset.amount > 0) {
      IERC20(principleAsset.token).safeTransfer(msg.sender, principleAsset.amount);
    }
    if (otherAsset.amount > 0) IERC20(otherAsset.token).safeTransfer(msg.sender, otherAsset.amount);
    IERC721(assets[0].token).safeTransferFrom(address(this), msg.sender, assets[0].tokenId);
  }

  function _decreaseLiquidity(
    Asset memory lpAsset,
    DecreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
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

    returnAssets = new Asset[](3);
    // Transfer assets to msg.sender
    returnAssets[0] = Asset(AssetType.ERC20, address(0), token0, 0, amount0Collected);
    returnAssets[1] = Asset(AssetType.ERC20, address(0), token1, 0, amount1Collected);
    returnAssets[2] = lpAsset;
  }

  function _optimalSwapFromPrinciple(
    uint256 amount,
    address pool,
    address token0,
    address token1,
    int24 tickLower,
    int24 tickUpper,
    bytes memory swapData
  ) internal returns (uint256 amount0Result, uint256 amount1Result) {
    (uint256 amount0, uint256 amount1) = principleToken == token0 ? (amount, 0) : (uint256(0), amount);
    if (amount0 > 0) IERC20(token0).approve(address(optimalSwapper), amount0);
    if (amount1 > 0) IERC20(token1).approve(address(optimalSwapper), amount1);
    (amount0Result, amount1Result) = optimalSwapper.optimalSwap(
      IOptimalSwapper.OptimalSwapParams(pool, amount0, amount1, tickLower, tickUpper, swapData)
    );
  }

  /// @notice Gets the underlying assets of the position
  /// @param asset The asset to get the underlying assets
  /// @return underlyingAssets The underlying assets of the position
  function getUnderlyingAssets(Asset memory asset) external view returns (Asset[] memory underlyingAssets) {
    require(asset.strategy == address(this), InvalidAsset());

    (uint256 amount0, uint256 amount1) = _getAmountsForPosition(INFPM(asset.token), asset.tokenId);

    (, , address token0, address token1, , , , , , , , ) = INFPM(asset.token).positions(asset.tokenId);
    underlyingAssets = new Asset[](2);
    underlyingAssets[0] = Asset(AssetType.ERC20, address(0), token0, 0, amount0);
    underlyingAssets[1] = Asset(AssetType.ERC20, address(0), token1, 0, amount1);
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

  receive() external payable {}
}
