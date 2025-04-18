// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../../libraries/AssetLib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IMerklStrategy } from "../../interfaces/strategies/IMerklStrategy.sol";

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
contract MerklStrategy is ReentrancyGuard, IStrategy {
  using SafeERC20 for IERC20;

  // Constants
  address private immutable thisAddress;
  address private immutable swapRouter;
  IConfigManager public immutable configManager;

  // Events
  event MerklRewardsClaimed(address indexed token, uint256 amount);

  /**
   * @notice Constructor
   * @param _configManager Address of the config manager
   */
  constructor(address _configManager) {
    require(_configManager != address(0), "Zero address");
    configManager = IConfigManager(_configManager);
    thisAddress = address(this);
  }

  /**
   * @notice Calculate the value of an asset in terms of the principal token
   * @param asset The asset to value
   * @param principalToken The principal token to value against
   * @return The value of the asset in terms of the principal token
   */
  function valueOf(AssetLib.Asset calldata asset, address principalToken) external view override returns (uint256) {
    return 0;
  }

  /**
   * @notice This function is used to claim Merkl rewwards, it does not convert any assets
   * @param assets The assets to convert
   * @param config The vault configuration
   * @param feeConfig The fee configuration
   * @param data Additional data for the conversion
   * @return The resulting assets after conversion
   */
  function convert(
    AssetLib.Asset[] calldata assets,
    VaultConfig calldata config,
    FeeConfig calldata feeConfig,
    bytes calldata data
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory) {
    require(assets.length == 0, InvalidNumberOfAssets());

    ClaimParams memory claimParams = abi.decode(data, (IMerklStrategy.ClaimParams));
    _claim(claimParams.distributor, claimParams.token, claimParams.amount, claimParams.proof);

    // Process the assets according to the strategy
    // This would typically involve claiming Merkl rewards

    // Return the processed assets
    AssetLib.Asset[] memory resultAssets = new AssetLib.Asset[](assets.length);
    for (uint256 i = 0; i < assets.length; i++) {
      resultAssets[i] = assets[i];
    }

    return resultAssets;
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
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory) { }

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
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory) { }

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
  ) external payable override nonReentrant returns (AssetLib.Asset[] memory) { }

  /**
   * @notice Validate that an asset can be used with this strategy
   * @param asset The asset to validate
   * @param config The vault configuration
   */
  function revalidate(AssetLib.Asset calldata asset, VaultConfig calldata config) external view override {
    require(asset.strategy == thisAddress, "InvalidAsset");

    // Validate that the asset is compatible with the strategy
    // For Merkl strategy, this might involve checking if the token is eligible for Merkl rewards
    // This is a simplified implementation

    // Check if the token is supported by the vault
    bool isSupported = false;
    for (uint256 i = 0; i < config.supportedAddresses.length; i++) {
      if (asset.token == config.supportedAddresses[i]) {
        isSupported = true;
        break;
      }
    }

    require(isSupported, "Token not supported");

    // Additional validation can be added here
  }

  function _claim(address distributor, address token, uint256 amount, bytes32[] calldata proofs) internal {
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

  function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes calldata swapData)
    internal
  {
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
        revert("Swap failed with no error message");
      }
    }
  }

  /// @dev some tokens require allowance == 0 to approve new amount
  /// but some tokens does not allow approve amount = 0
  /// we try to set allowance = 0 before approve new amount. if it revert means that
  /// the token not allow to approve 0, which means the following line code will work properly
  function _safeResetAndApprove(IERC20 token, address _spender, uint256 _value) internal {
    /// @dev omitted approve(0) result because it might fail and does not break the flow
    address(token).call(abi.encodeWithSelector(token.approve.selector, _spender, 0));

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
    require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), "SafeERC20: approve failed");
  }

  /**
   * @notice Receive ETH
   */
  receive() external payable { }
}
