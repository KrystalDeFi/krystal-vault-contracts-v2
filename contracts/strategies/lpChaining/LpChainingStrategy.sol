// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "../../interfaces/strategies/IStrategy.sol";
import "../../interfaces/core/IConfigManager.sol";
import "../../interfaces/strategies/lpChaining/ILpChainingStrategy.sol";

contract LpChainingStrategy is ILpChainingStrategy, ERC721Holder {
  using SafeERC20 for IERC20;

  IConfigManager public immutable configManager;

  constructor(address _configManager) {
    require(_configManager != address(0), ZeroAddress());

    configManager = IConfigManager(_configManager);
  }

  /// @notice Get value of the asset in terms of principalToken
  /// @param asset The asset to get the value
  /// @param principalToken The principal token
  /// @return valueInPrincipal The value of the asset in terms of principalToken
  function valueOf(AssetLib.Asset calldata asset, address principalToken)
    external
    view
    returns (uint256 valueInPrincipal)
  { }

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
  ) external payable returns (AssetLib.Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));

    uint8 instructionType = instruction.instructionType;

    ChainingInstruction[] memory instructions = abi.decode(instruction.params, (ChainingInstruction[]));

    uint256 increaseInstructionCount;
    for (uint256 i; i < instructions.length;) {
      require(configManager.isWhitelistedStrategy(instructions[i].strategy), InvalidStrategy());
      if (instructions[i].instructionType == InstructionType.SwapAndIncreaseLiquidity) increaseInstructionCount++;

      unchecked {
        i++;
      }
    }

    require(instructions.length == assets.length - increaseInstructionCount, InvalidNumberOfAssets());

    if (instructionType == uint8(ChainingInstructionType.Batch)) {
      require(!_isIncludedDecrease(instructions), InvalidInstructionType());

      return _batch(assets, instructions, vaultConfig, feeConfig);
    } else if (instructionType == uint8(ChainingInstructionType.DecreaseAndBatch)) {
      require(_isIncludedDecrease(instructions), InvalidInstructionType());

      return _decreaseAndBatch(assets, instructions, vaultConfig, feeConfig);
    }

    revert InvalidInstructionType();
  }

  function _batch(
    AssetLib.Asset[] memory assets,
    ChainingInstruction[] memory instructions,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    AssetLib.Asset[][] memory tempAssets = new AssetLib.Asset[][](instructions.length);

    uint256 totalLength;
    uint256 assetIndex;

    for (uint256 i; i < instructions.length;) {
      uint8 assetGroupSize = instructions[i].instructionType == InstructionType.SwapAndIncreaseLiquidity ? 2 : 1;

      AssetLib.Asset[] memory assetsData = new AssetLib.Asset[](assetGroupSize);

      for (uint256 j; j < assetGroupSize;) {
        assetsData[j] = assets[assetIndex + j];

        unchecked {
          j++;
        }
      }

      assetIndex += assetGroupSize;

      if (
        instructions[i].instructionType == InstructionType.SwapAndMintPosition
          || instructions[i].instructionType == InstructionType.SwapAndIncreaseLiquidity
      ) require(assetsData[0].token == vaultConfig.principalToken, InvalidAsset());

      bytes memory cData = abi.encodeWithSelector(
        IStrategy.convert.selector,
        assetsData,
        vaultConfig,
        feeConfig,
        abi.encode(Instruction(uint8(instructions[i].instructionType), instructions[i].params))
      );

      bytes memory returnData = _delegateCallToLpStrategy(instructions[i].strategy, cData);

      AssetLib.Asset[] memory newAssets = abi.decode(returnData, (AssetLib.Asset[]));
      tempAssets[i] = newAssets;
      totalLength += newAssets.length;

      unchecked {
        i++;
      }
    }

    returnAssets = new AssetLib.Asset[](totalLength);
    uint256 k;
    for (uint256 i; i < tempAssets.length;) {
      AssetLib.Asset[] memory arr = tempAssets[i];
      for (uint256 j; j < arr.length;) {
        returnAssets[k] = arr[j];
        unchecked {
          k++;
          j++;
        }
      }
      unchecked {
        i++;
      }
    }
  }

  function _decreaseAndBatch(
    AssetLib.Asset[] memory assets,
    ChainingInstruction[] memory instructions,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata feeConfig
  ) internal returns (AssetLib.Asset[] memory returnAssets) {
    AssetLib.Asset[][] memory tempAssets = new AssetLib.Asset[][](instructions.length);

    uint256 totalLength;
    uint256 assetIndex;
    uint256 amountToReduce;

    for (uint256 i; i < instructions.length;) {
      uint8 assetGroupSize = instructions[i].instructionType == InstructionType.SwapAndIncreaseLiquidity ? 2 : 1;

      AssetLib.Asset[] memory assetsData = new AssetLib.Asset[](assetGroupSize);

      for (uint256 j; j < assetGroupSize;) {
        assetsData[j] = assets[assetIndex + j];

        unchecked {
          j++;
        }
      }

      assetIndex += assetGroupSize;

      ModifiedAddonPrincipalAmountParams memory modifiedParams =
        abi.decode(instructions[i].params, (ModifiedAddonPrincipalAmountParams));

      if (
        instructions[i].instructionType == InstructionType.SwapAndMintPosition
          || instructions[i].instructionType == InstructionType.SwapAndIncreaseLiquidity
      ) {
        require(assetsData[0].token == vaultConfig.principalToken, InvalidAsset());
        assetsData[0].amount += modifiedParams.addonPrincipalAmount;
        amountToReduce += modifiedParams.addonPrincipalAmount;
      }

      bytes memory cData = abi.encodeWithSelector(
        IStrategy.convert.selector,
        assetsData,
        vaultConfig,
        feeConfig,
        abi.encode(Instruction(uint8(instructions[i].instructionType), modifiedParams.params))
      );

      bytes memory returnData = _delegateCallToLpStrategy(instructions[i].strategy, cData);

      AssetLib.Asset[] memory newAssets = abi.decode(returnData, (AssetLib.Asset[]));
      tempAssets[i] = newAssets;
      totalLength += newAssets.length;

      unchecked {
        i++;
      }
    }

    if (amountToReduce > 0) {
      bool done;
      for (uint256 i; i < tempAssets.length && !done;) {
        for (uint256 j; j < tempAssets[i].length && !done;) {
          if (tempAssets[i][j].token == vaultConfig.principalToken) {
            if (tempAssets[i][j].amount >= amountToReduce) {
              tempAssets[i][j].amount -= amountToReduce;
              amountToReduce = 0;
              done = true;
              break;
            } else {
              amountToReduce -= tempAssets[i][j].amount;
              tempAssets[i][j].amount = 0;
            }
          }
          unchecked {
            j++;
          }
        }
        unchecked {
          i++;
        }
      }

      // amountToReduce must be 0 after reducing all principal token amounts from decreased positions
      require(amountToReduce == 0, InvalidAsset());
    }

    returnAssets = new AssetLib.Asset[](totalLength);
    uint256 k;
    for (uint256 i; i < tempAssets.length;) {
      AssetLib.Asset[] memory arr = tempAssets[i];
      for (uint256 j; j < arr.length;) {
        returnAssets[k] = arr[j];
        unchecked {
          k++;
          j++;
        }
      }
      unchecked {
        i++;
      }
    }
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
  ) external payable returns (AssetLib.Asset[] memory) { }

  /// @notice convert the asset from the principal token
  /// @param existingAsset The existing asset to convert
  /// @param principalTokenAmount The amount of principal token
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function convertFromPrincipal(
    AssetLib.Asset calldata existingAsset,
    uint256 principalTokenAmount,
    VaultConfig calldata vaultConfig
  ) external payable returns (AssetLib.Asset[] memory) { }

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
  ) external payable returns (AssetLib.Asset[] memory returnAssets) { }

  /// @notice Revalidate the position
  /// @param asset The asset to revalidate
  /// @param config The vault configuration
  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external view { }

  function _delegateCallToLpStrategy(address strategy, bytes memory cData) internal returns (bytes memory returnData) {
    bool success;
    (success, returnData) = strategy.delegatecall(cData);
    if (!success) {
      if (returnData.length == 0) revert StrategyDelegateCallFailed();
      assembly {
        let returnDataSize := mload(returnData)
        revert(add(32, returnData), returnDataSize)
      }
    }
  }

  function _isIncludedDecrease(ChainingInstruction[] memory instructions) internal pure returns (bool) {
    for (uint256 i; i < instructions.length;) {
      if (instructions[i].instructionType == InstructionType.DecreaseLiquidityAndSwap) return true;

      unchecked {
        i++;
      }
    }
    return false;
  }

  /// @notice Fallback function to receive Ether. This is required for the contract to accept ETH transfers.
  receive() external payable { }
}
