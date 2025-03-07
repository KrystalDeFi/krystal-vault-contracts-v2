// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../../interfaces/strategies/ILpStrategy.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract LpStrategyImpl is Initializable, ReentrancyGuardUpgradeable, ILpStrategy {
  using SafeERC20 for IERC20;

  address public principalToken;

  constructor() {}

  function initialize(address _principalToken) public initializer {
    __ReentrancyGuard_init();

    principalToken = _principalToken;
  }

  /// @notice Deposits the asset to the strategy
  function valueOf(Asset memory asset) external view returns (uint256 value) {
    INFPM(asset.token).positions(asset.tokenId);
  }

  /// @notice Converts the asset to another assets
  function convert(Asset[] memory assets, bytes calldata data) external returns (Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));
    if (instruction.instructionType == InstructionType.MintPosition) {
      MintPositionParams memory params = abi.decode(instruction.params, (MintPositionParams));
      returnAssets = _mintPosition(assets, params);
    } else if (instruction.instructionType == InstructionType.IncreaseLiquidity) {
      IncreaseLiquidityParams memory params = abi.decode(instruction.params, (IncreaseLiquidityParams));
      returnAssets = _increaseLiquidity(assets, params);
    } else if (instruction.instructionType == InstructionType.DecreaseLiquidity) {
      DecreaseLiquidityParams memory params = abi.decode(instruction.params, (DecreaseLiquidityParams));
      returnAssets = _decreaseLiquidity(assets, params);
    }
    revert InvalidInstructionType();
  }

  function convertIntoExisting(
    Asset memory existingAsset,
    Asset[] memory newAssets,
    bytes calldata data
  ) external returns (Asset[] memory asset) {}

  /// @notice Mints a new position
  /// @param assets The assets to mint the position, assets[0] = token0, assets[1] = token1
  /// @param params The parameters for minting the position
  /// @return returnAssets The assets that were returned to the msg.sender
  function _mintPosition(
    Asset[] memory assets,
    MintPositionParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 2, InvalidNumberOfAssets());
    require(assets[0].token == principalToken || assets[1].token == principalToken, InvalidAsset());

    (Asset memory token0, Asset memory token1) = assets[0].token < assets[1].token
      ? (assets[0], assets[1])
      : (assets[1], assets[0]);

    IERC20(token0.token).safeTransferFrom(msg.sender, address(this), token0.amount);
    IERC20(token1.token).safeTransferFrom(msg.sender, address(this), token1.amount);

    IERC20(token0.token).approve(address(params.nfpm), token0.amount);
    IERC20(token1.token).approve(address(params.nfpm), token1.amount);

    returnAssets = new Asset[](3);
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
    returnAssets[0] = Asset(address(0), token0.token, 0, token0.amount - amount0);
    returnAssets[1] = Asset(address(0), token1.token, 0, token1.amount - amount1);
    returnAssets[2] = Asset(address(this), address(params.nfpm), tokenId, 1);

    // Transfer assets to msg.sender
    IERC20(token0.token).safeTransfer(msg.sender, token0.amount - amount0);
    IERC20(token1.token).safeTransfer(msg.sender, token1.amount - amount1);
    IERC721(params.nfpm).safeTransferFrom(address(this), msg.sender, tokenId);
  }

  /// @notice Increases the liquidity of the position
  /// @param assets The assets to increase the liquidity assets[2] = lpAsset
  /// @param params The parameters for increasing the liquidity
  /// @return returnAssets The assets that were returned to the msg.sender
  function _increaseLiquidity(
    Asset[] memory assets,
    IncreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 3, InvalidNumberOfAssets());

    Asset memory lpAsset = assets[2];
    (Asset memory token0, Asset memory token1) = assets[0].token < assets[1].token
      ? (assets[0], assets[1])
      : (assets[1], assets[0]);

    IERC20(token0.token).safeTransferFrom(msg.sender, address(this), token0.amount);
    IERC20(token1.token).safeTransferFrom(msg.sender, address(this), token1.amount);

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

    returnAssets = new Asset[](2);
    returnAssets[0] = Asset(address(0), token0.token, 0, token0.amount - amount0Added);
    returnAssets[1] = Asset(address(0), token1.token, 0, token1.amount - amount1Added);

    // Transfer assets to msg.sender
    IERC20(token0.token).safeTransfer(msg.sender, token0.amount - amount0Added);
    IERC20(token1.token).safeTransfer(msg.sender, token1.amount - amount1Added);
  }

  /// @notice Decreases the liquidity of the position
  /// @param assets The assets to decrease the liquidity assets[0] = lpAsset
  /// @param params The parameters for decreasing the liquidity
  /// @return returnAssets The assets that were returned to the msg.sender
  function _decreaseLiquidity(
    Asset[] memory assets,
    DecreaseLiquidityParams memory params
  ) internal returns (Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());
    Asset memory lpAsset = assets[0];
    IERC721(lpAsset.token).safeTransferFrom(msg.sender, lpAsset.token, lpAsset.amount);
    INFPM(lpAsset.token).collect(
      INFPM.CollectParams(lpAsset.tokenId, address(this), type(uint128).max, type(uint128).max)
    );
    (uint256 amount0Collected, uint256 amount1Collected) = INFPM(lpAsset.token).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams(
        lpAsset.tokenId,
        params.liquidity,
        params.amount0Min,
        params.amount1Min,
        block.timestamp
      )
    );
    (, , address token0, address token1, , , , , , , , ) = INFPM(lpAsset.token).positions(lpAsset.tokenId);

    returnAssets = new Asset[](3);
    // Transfer assets to msg.sender
    returnAssets[0] = Asset(address(0), token0, 0, amount0Collected);
    returnAssets[1] = Asset(address(0), token1, 0, amount1Collected);
    returnAssets[2] = lpAsset;

    IERC721(lpAsset.token).safeTransferFrom(address(this), msg.sender, lpAsset.tokenId);
    IERC20(token0).safeTransfer(msg.sender, amount0Collected);
    IERC20(token1).safeTransfer(msg.sender, amount1Collected);
  }

  receive() external payable {}
}
