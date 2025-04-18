// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "../../interfaces/strategies/IStrategy.sol";

contract MerklStrategy is IStrategy {

}
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../../interfaces/strategies/IStrategy.sol";
import "../../interfaces/IWETH9.sol";
import "../../libraries/AssetLib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MerklStrategy
 * @notice Strategy for handling Merkl rewards for LP positions
 */
contract MerklStrategy is ReentrancyGuard, IStrategy {
    using SafeERC20 for IERC20;

    // Constants
    address private immutable thisAddress;
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
    function valueOf(AssetLib.Asset calldata asset, address principalToken) 
        external 
        view 
        override 
        returns (uint256) 
    {
        require(asset.strategy == thisAddress, "InvalidAsset");
        
        // For Merkl rewards, the value is typically the amount of the token
        // If the asset token is the principal token, return the amount directly
        if (asset.token == principalToken) {
            return asset.amount;
        }
        
        // Otherwise, we would need to get the value through a price oracle or other mechanism
        // This is a simplified implementation
        return 0;
    }

    /**
     * @notice Convert assets according to the strategy
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
    ) 
        external 
        payable 
        override 
        nonReentrant 
        returns (AssetLib.Asset[] memory) 
    {
        require(assets.length > 0, "InvalidNumberOfAssets");
        
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
    ) 
        external 
        payable 
        override 
        nonReentrant 
        returns (AssetLib.Asset[] memory) 
    {
        require(asset.strategy == thisAddress, "InvalidAsset");
        
        // Claim Merkl rewards
        // This would involve interacting with the Merkl distribution contract
        
        // For demonstration, we'll assume rewards are already in this contract
        uint256 rewardAmount = IERC20(tokenOut).balanceOf(address(this));
        require(rewardAmount >= amountTokenOutMin, "InsufficientAmountOut");
        
        // Calculate and transfer fees
        uint256 platformFee = (rewardAmount * feeConfig.platformFeeBasisPoint) / 10000;
        uint256 ownerFee = (rewardAmount * feeConfig.vaultOwnerFeeBasisPoint) / 10000;
        uint256 netAmount = rewardAmount - platformFee - ownerFee;
        
        if (platformFee > 0 && feeConfig.platformFeeRecipient != address(0)) {
            IERC20(tokenOut).safeTransfer(feeConfig.platformFeeRecipient, platformFee);
            emit FeeCollected(FeeType.PLATFORM, feeConfig.platformFeeRecipient, tokenOut, platformFee);
        }
        
        if (ownerFee > 0 && feeConfig.vaultOwner != address(0)) {
            IERC20(tokenOut).safeTransfer(feeConfig.vaultOwner, ownerFee);
            emit FeeCollected(FeeType.OWNER, feeConfig.vaultOwner, tokenOut, ownerFee);
        }
        
        // Create result asset with the harvested rewards
        AssetLib.Asset[] memory resultAssets = new AssetLib.Asset[](1);
        resultAssets[0] = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: tokenOut,
            tokenId: 0,
            amount: netAmount
        });
        
        emit MerklRewardsClaimed(tokenOut, netAmount);
        
        return resultAssets;
    }

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
    ) 
        external 
        payable 
        override 
        nonReentrant 
        returns (AssetLib.Asset[] memory) 
    {
        require(existingAsset.strategy == thisAddress, "InvalidAsset");
        
        // For Merkl strategy, this might involve staking tokens in a pool that's eligible for Merkl rewards
        // This is a simplified implementation
        
        AssetLib.Asset[] memory resultAssets = new AssetLib.Asset[](1);
        resultAssets[0] = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: thisAddress,
            token: config.principalToken,
            tokenId: 0,
            amount: principalTokenAmount
        });
        
        return resultAssets;
    }

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
    ) 
        external 
        payable 
        override 
        nonReentrant 
        returns (AssetLib.Asset[] memory) 
    {
        require(existingAsset.strategy == thisAddress, "InvalidAsset");
        
        // Calculate the proportion of the asset to convert based on shares
        uint256 assetAmount = (existingAsset.amount * shares) / totalSupply;
        
        // For Merkl strategy, this might involve unstaking tokens from a pool
        // This is a simplified implementation
        
        // Calculate and transfer fees
        uint256 platformFee = (assetAmount * feeConfig.platformFeeBasisPoint) / 10000;
        uint256 ownerFee = (assetAmount * feeConfig.vaultOwnerFeeBasisPoint) / 10000;
        uint256 netAmount = assetAmount - platformFee - ownerFee;
        
        if (platformFee > 0 && feeConfig.platformFeeRecipient != address(0)) {
            emit FeeCollected(FeeType.PLATFORM, feeConfig.platformFeeRecipient, existingAsset.token, platformFee);
        }
        
        if (ownerFee > 0 && feeConfig.vaultOwner != address(0)) {
            emit FeeCollected(FeeType.OWNER, feeConfig.vaultOwner, existingAsset.token, ownerFee);
        }
        
        AssetLib.Asset[] memory resultAssets = new AssetLib.Asset[](1);
        resultAssets[0] = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: config.principalToken,
            tokenId: 0,
            amount: netAmount
        });
        
        return resultAssets;
    }

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

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
