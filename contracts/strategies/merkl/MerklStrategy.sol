// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libraries/AssetLib.sol";

import "../../interfaces/core/IConfigManager.sol";
import { IMerklStrategy } from "../../interfaces/strategies/IMerklStrategy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IFeeTaker } from "../../interfaces/strategies/IFeeTaker.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

interface IMerklDistributor {
  function claim(
    address[] calldata users,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[][] calldata proofs
  ) external;
}

/**
 * @title MerklStrategy
 * @notice Strategy for handling Merkl rewards for LP positions
 */
contract MerklStrategy is IMerklStrategy {
  uint256 internal constant Q64 = 0x10000000000000000;

  using SafeERC20 for IERC20;

  // Constants
  address private immutable thisAddress;
  IConfigManager private immutable configManager;

  // Events
  event MerklRewardsClaimed(address indexed token, uint256 amount, address principalToken, uint256 principalAmount);

  /**
   * @notice Constructor
   * @param _configManager Address of the config manager
   */
  constructor(address _configManager) {
    require(_configManager != address(0), ZeroAddress());

    configManager = IConfigManager(_configManager);
    thisAddress = address(this);
  }

  /**
   * @notice Cannot be calculated
   * @return 0
   */
  function valueOf(AssetLib.Asset calldata, address) external pure override returns (uint256) {
    return 0;
  }

  /**
   * @notice This function is used to claim Merkl rewwards, it does not convert any assets
   * @param assets The assets passed must be an empty array
   * @param config The vault configuration
   * @param feeConfig The fee configuration
   * @param data Additional data for the conversion
   * @return returnAssets The resulting assets after conversion
   */
  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external payable override returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 0, InvalidNumberOfAssets());

    Instruction memory instruction = abi.decode(data, (Instruction));
    if (instruction.instructionType == uint8(IMerklStrategy.InstructionType.ClaimAndSwap)) {
      return _claimAndSwap(config, feeConfig, instruction.params);
    } else {
      revert InvalidInstructionType();
    }
  }

  /**
   * @notice Harvest rewards from an asset
   * @param asset The asset to harvest from
   * @param tokenOut The token to receive as rewards
   * @param amountTokenOutMin The minimum amount of tokens to receive
   * @param vaultConfig The vault configuration
   * @param feeConfig The fee configuration
   * @return The resulting assets after harvesting
   */
  function harvest(
    AssetLib.Asset calldata asset,
    address tokenOut,
    uint256 amountTokenOutMin,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) external payable override returns (AssetLib.Asset[] memory) { }

  /**
   * @notice Convert principal token to strategy assets
   * @param existingAsset The existing asset to convert from
   * @param principalTokenAmount The amount of principal token to convert
   * @param config The vault configuration
   * @return The resulting assets after conversion
   */
  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata config
  ) external payable override returns (AssetLib.Asset[] memory) { }

  /**
   * @notice Convert strategy assets to principal token
   * @param existingAsset The existing asset to convert from
   * @param shares The number of shares to convert
   * @param totalSupply The total supply of shares
   * @param config The vault configuration
   * @param feeConfig The fee configuration
   * @return The resulting assets after conversion
   */
  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256 totalSupply,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig
  ) external payable override returns (AssetLib.Asset[] memory) { }

  /**
   * @notice Validate that an asset can be used with this strategy
   * @param asset The asset to validate
   * @param config The vault configuration
   */
  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external view override { }

  function _claimAndSwap(VaultConfig calldata config, FeeConfig calldata feeConfig, bytes memory data)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    ClaimAndSwapParams memory claimParams = abi.decode(data, (IMerklStrategy.ClaimAndSwapParams));

    // Verify the signer is whitelisted
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        claimParams.distributor,
        claimParams.token,
        claimParams.amount,
        claimParams.proof,
        claimParams.swapRouter,
        claimParams.swapData,
        claimParams.amountOutMin,
        claimParams.deadline
      )
    );
    address signer = ECDSA.recover(messageHash, claimParams.signature);
    require(configManager.isWhitelistSigner(signer), InvalidSigner());
    require(block.timestamp <= claimParams.deadline, SignatureExpired());

    address tokenIn = claimParams.token;
    address tokenOut = config.principalToken;
    uint256 amountInBefore = IERC20(tokenIn).balanceOf(address(this));
    uint256 amountOutBefore = IERC20(tokenOut).balanceOf(address(this));

    _claim(claimParams.distributor, tokenIn, claimParams.amount, claimParams.proof);
    uint256 amountClaimed = IERC20(tokenIn).balanceOf(address(this)) - amountInBefore;

    _swap(tokenIn, amountClaimed, claimParams.swapRouter, claimParams.swapData);

    uint256 amountIn = IERC20(tokenIn).balanceOf(address(this)) - amountInBefore;
    uint256 amountOut = IERC20(tokenOut).balanceOf(address(this)) - amountOutBefore;

    require(amountOut >= claimParams.amountOutMin, NotEnoughAmountOut());
    if (amountIn > 0) amountIn -= _takeFee(tokenIn, amountIn, feeConfig);
    if (amountOut > 0) amountOut -= _takeFee(tokenOut, amountOut, feeConfig);

    returnAssets = new AssetLib.Asset[](2);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), tokenIn, 0, amountIn);
    returnAssets[1] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), tokenOut, 0, amountOut);
    emit MerklRewardsClaimed(tokenIn, amountClaimed, tokenOut, returnAssets[1].amount);
  }

  function _claim(address distributor, address token, uint256 amount, bytes32[] memory proofs) internal {
    address[] memory users = new address[](1);
    users[0] = address(this);
    address[] memory tokens = new address[](1);
    tokens[0] = token;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;
    bytes32[][] memory proofsArray = new bytes32[][](1);
    proofsArray[0] = proofs;

    IMerklDistributor(distributor).claim(users, tokens, amounts, proofsArray);
  }

  function _swap(address tokenIn, uint256 amountIn, address swapRouter, bytes memory swapData) internal {
    require(configManager.isWhitelistedSwapRouter(swapRouter), InvalidSwapRouter());
    // Implement the swap logic here
    // This could involve calling a DEX router or other swap mechanism
    _safeApprove(IERC20(tokenIn), swapRouter, amountIn);
    // execute swap
    (bool success, bytes memory returnData) = swapRouter.call(swapData);
    // Implement revert using returnData as error message
    if (!success) {
      // If there's return data, extract the error message
      if (returnData.length > 0) {
        // First try to extract the revert reason from the returnData
        assembly {
          let returnDataSize := mload(returnData)
          revert(add(32, returnData), returnDataSize)
        }
      } else {
        revert SwapFailed();
      }
    }
  }

  /// @dev some tokens require allowance == 0 to approve new amount
  /// but some tokens does not allow approve amount = 0
  /// we try to set allowance = 0 before approve new amount. if it revert means that
  /// the token not allow to approve 0, which means the following line code will work properly
  function _safeResetAndApprove(IERC20 token, address _spender, uint256 _value) internal {
    /// @dev omitted approve(0) result because it might fail and does not break the flow
    (bool success,) = address(token).call(abi.encodeWithSelector(token.approve.selector, _spender, 0));
    require(success, ApproveFailed());

    /// @dev value for approval after reset must greater than 0
    require(_value > 0);
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

  /**
   * @notice Receive ETH
   */
  receive() external payable { }
}
