// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "../../interfaces/core/IVaultFactory.sol";
import "../../interfaces/strategies/vault/IVaultStrategy.sol";
import { IVault } from "../../interfaces/core/IVault.sol";

contract VaultStrategy is ReentrancyGuard, IVaultStrategy {
  using SafeERC20 for IERC20;

  IVaultFactory public immutable vaultFactory;
  address private immutable thisAddress;

  constructor(address _vaultFactory) {
    if (_vaultFactory == address(0)) revert ZeroAddress();
    vaultFactory = IVaultFactory(_vaultFactory);
    thisAddress = address(this);
  }

  /// @notice Get value of the asset in terms of principalToken
  /// @param asset The asset to get the value
  /// @return valueInPrincipal The value of the asset in terms of principalToken
  function valueOf(AssetLib.Asset calldata asset, address) external view returns (uint256) {
    uint256 totalValue = IVault(asset.token).getTotalValue();
    uint256 totalSupply = IERC20(asset.token).totalSupply();
    if (totalSupply == 0 || asset.amount == 0) return 0;
    return FullMath.mulDiv(asset.amount, totalValue, totalSupply);
  }

  /// @notice Converts the asset to another assets
  /// @param assets The assets to convert
  /// @param vaultConfig The vault configuration
  /// @param data The data for the instruction
  /// @return returnAssets The assets that were returned to the msg.sender
  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata vaultConfig,
    FeeConfig calldata,
    bytes calldata data
  ) external payable nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    Instruction memory instruction = abi.decode(data, (Instruction));
    uint8 instructionType = instruction.instructionType;

    if (instructionType == uint8(InstructionType.Deposit)) {
      return _deposit(assets, abi.decode(instruction.params, (DepositParams)), vaultConfig);
    }

    if (instructionType == uint8(InstructionType.Withdraw)) {
      return _withdraw(assets, abi.decode(instruction.params, (WithdrawParams)), vaultConfig);
    }

    revert InvalidInstructionType();
  }

  /// @notice Deposit assets into the vault
  /// @param assets The assets to deposit
  /// @param params The deposit parameters
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function _deposit(AssetLib.Asset[] memory assets, DepositParams memory params, VaultConfig calldata vaultConfig)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(vaultFactory.isVault(params.vault), InvalidVault());

    address principalToken = vaultConfig.principalToken;
    (,,, address targetPrincipalToken,) = IVault(params.vault).getVaultConfig();
    require(principalToken == targetPrincipalToken, PrincipalTokenMismatch());

    uint256 shares = IVault(params.vault).deposit(params.principalAmount, params.minShares);

    returnAssets = new AssetLib.Asset[](1);
    returnAssets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: thisAddress,
      token: params.vault,
      tokenId: 0,
      amount: shares
    });
  }

  /// @notice Withdraw assets from the vault
  /// @param assets The assets to withdraw
  /// @param params The withdraw parameters
  /// @param vaultConfig The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function _withdraw(AssetLib.Asset[] memory assets, WithdrawParams memory params, VaultConfig calldata vaultConfig)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    require(assets.length == 1, InvalidNumberOfAssets());
    require(vaultFactory.isVault(assets[0].token), InvalidVault());

    uint256 amount = IVault(assets[0].token).withdraw(params.shares, params.unwrap, params.minReturnAmount);

    returnAssets = new AssetLib.Asset[](1);
    returnAssets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      strategy: address(0),
      token: vaultConfig.principalToken,
      tokenId: 0,
      amount: amount
    });
  }

  /// @notice Harvest the asset fee
  /// @param asset The asset to harvest
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  /// @return returnAssets The assets that were returned to the msg.sender
  function harvest(
    AssetLib.Asset calldata asset,
    address,
    uint256 amountTokenOutMin,
    VaultConfig calldata,
    FeeConfig calldata
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    returnAssets = IVault(asset.token).harvest(asset, amountTokenOutMin);
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
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = existingAsset;
    return _deposit(
      assets,
      DepositParams({
        vault: existingAsset.token,
        principalAmount: principalTokenAmount,
        minShares: 0 // Minimum shares to receive
       }),
      vaultConfig
    );
  }

  /// @notice convert the asset to the principal token
  /// @param existingAsset The existing asset to convert
  /// @param shares The shares to convert
  /// @param config The vault configuration
  /// @return returnAssets The assets that were returned to the msg.sender
  function convertToPrincipal(
    AssetLib.Asset memory existingAsset,
    uint256 shares,
    uint256,
    VaultConfig calldata config,
    FeeConfig calldata
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory returnAssets) {
    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = existingAsset;
    return _withdraw(
      assets,
      WithdrawParams({
        shares: shares,
        unwrap: false, // Unwrap is false by default
        minReturnAmount: 0 // Minimum return amount to receive
       }),
      config
    );
  }

  /// @notice Revalidate the position
  /// @param asset The asset to revalidate
  /// @param config The vault configuration
  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external { }

  /// @notice Fallback function to receive Ether. This is required for the contract to accept ETH transfers.
  receive() external payable { }
}
