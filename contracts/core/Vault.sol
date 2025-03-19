// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/strategies/IStrategy.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/core/IConfigManager.sol";
import { AssetLib } from "../libraries/AssetLib.sol";
import { InventoryLib } from "../libraries/InventoryLib.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract Vault is AccessControlUpgradeable, ERC20PermitUpgradeable, ReentrancyGuard, IVault, ERC721Holder {
  using SafeERC20 for IERC20;

  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;
  using InventoryLib for InventoryLib.Inventory;

  uint256 public constant SHARES_PRECISION = 1e4;
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  IConfigManager public configManager;

  address public override vaultOwner;
  VaultConfig private vaultConfig;

  InventoryLib.Inventory private inventory;

  modifier onlyAdminOrAutomator() {
    require(
      hasRole(ADMIN_ROLE_HASH, _msgSender()) || configManager.isWhitelistedAutomator(_msgSender()), Unauthorized()
    );
    _;
  }

  /// @notice Initializes the vault
  /// @param params Vault creation parameters
  /// @param _owner Owner of the vault
  /// @param _configManager Address of the whitelist manager
  function initialize(VaultCreateParams memory params, address _owner, address _configManager) public initializer {
    require(params.config.principalToken != address(0), ZeroAddress());
    require(_configManager != address(0), ZeroAddress());

    __ERC20_init(params.name, params.symbol);
    __ERC20Permit_init(params.name);
    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(ADMIN_ROLE_HASH, _owner);

    configManager = IConfigManager(_configManager);
    vaultOwner = _owner;
    vaultConfig = params.config;
    AssetLib.Asset memory firstAsset =
      AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), params.config.principalToken, 0, params.principalTokenAmount);

    inventory.addAsset(firstAsset);
    _mint(_owner, params.principalTokenAmount * SHARES_PRECISION);

    emit Deposit(_owner, params.principalTokenAmount * SHARES_PRECISION);
  }

  /// @notice Deposits the asset to the vault
  /// @param principalAmount Amount of in principalToken
  /// @return shares Amount of shares minted
  function deposit(uint256 principalAmount, uint256 minShares) external nonReentrant returns (uint256 shares) {
    require(_msgSender() == vaultOwner || vaultConfig.allowDeposit, DepositNotAllowed());
    for (uint256 i = 0; i < inventory.assets.length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0)) _harvest(currentAsset);
      unchecked {
        i++;
      }
    }
    address principalToken = vaultConfig.principalToken;
    uint256 totalSupply = totalSupply();
    uint256 totalValue = getTotalValue();

    shares =
      totalSupply == 0 ? principalAmount * SHARES_PRECISION : FullMath.mulDiv(principalAmount, totalSupply, totalValue);
    require(shares >= minShares, InsufficientShares());

    IERC20(vaultConfig.principalToken).safeTransferFrom(_msgSender(), address(this), principalAmount);
    inventory.addAsset(
      AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), vaultConfig.principalToken, 0, principalAmount)
    );

    for (uint256 i = 0; i < inventory.assets.length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0)) {
        uint256 strategyPosValue = IStrategy(currentAsset.strategy).valueOf(currentAsset, principalToken);
        uint256 pAmountForStrategy = FullMath.mulDiv(principalAmount, strategyPosValue, totalValue);
        _transferAsset(currentAsset, currentAsset.strategy);
        _transferAsset(
          AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), principalToken, 0, pAmountForStrategy),
          currentAsset.strategy
        );
        _addAssets(IStrategy(currentAsset.strategy).convertFromPrincipal(currentAsset, pAmountForStrategy, vaultConfig));
      }
      unchecked {
        i++;
      }
    }

    _mint(_msgSender(), shares);
    emit Deposit(_msgSender(), shares);

    return shares;
  }

  /// @notice Withdraws the asset from the vault
  /// @param shares Amount of shares to be burned
  function withdraw(uint256 shares) external nonReentrant {
    require(shares != 0, InvalidShares());
    uint256 totalSupply = totalSupply();

    _burn(_msgSender(), shares);

    for (uint256 i = 0; i < inventory.assets.length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0)) {
        _transferAsset(currentAsset, currentAsset.strategy);
        AssetLib.Asset[] memory assets =
          IStrategy(currentAsset.strategy).convertToPrincipal(currentAsset, shares, totalSupply, vaultConfig);
        _addAssets(assets);
        _transferAssets(assets, _msgSender());
      } else if (currentAsset.assetType == AssetLib.AssetType.ERC20) {
        currentAsset.amount = FullMath.mulDiv(currentAsset.amount, shares, totalSupply);
        _transferAsset(currentAsset, _msgSender());
      }
      unchecked {
        i++;
      }
    }

    emit Withdraw(_msgSender(), shares);
  }

  /// @notice Allocates un-used assets to the strategy
  /// @param inputAssets Input assets to allocate
  /// @param strategy Strategy to allocate to
  /// @param data Data for the strategy
  function allocate(AssetLib.Asset[] memory inputAssets, IStrategy strategy, bytes calldata data)
    external
    onlyAdminOrAutomator
  {
    require(configManager.isWhitelistedStrategy(address(strategy)), InvalidStrategy());

    // validate if number of assets that have strategy != address(0) < configManager.maxPositions
    uint8 strategyCount = 0;
    for (uint256 i = 0; i < inventory.assets.length;) {
      if (inventory.assets[i].strategy != address(0)) strategyCount++;
      unchecked {
        i++;
      }
    }
    require(strategyCount < configManager.maxPositions(), MaxPositionsReached());

    AssetLib.Asset memory currentAsset;

    for (uint256 i = 0; i < inputAssets.length;) {
      require(inputAssets[i].amount != 0, InvalidAssetAmount());

      currentAsset = inventory.getAsset(inputAssets[i].token, inputAssets[i].tokenId);
      require(currentAsset.amount >= inputAssets[i].amount, InvalidAssetAmount());
      // Only allow allocation to a strategy if the asset is not already allocated and is ERC20
      require(currentAsset.strategy == address(0), InvalidAssetStrategy());
      require(currentAsset.assetType == AssetLib.AssetType.ERC20, InvalidAssetType());

      _transferAsset(inputAssets[i], address(strategy));

      unchecked {
        i++;
      }
    }

    AssetLib.Asset[] memory newAssets = strategy.convert(inputAssets, vaultConfig, data);
    _addAssets(newAssets);

    emit Allocate(inputAssets, strategy, newAssets);
  }

  /// @notice Deallocates the assets from the strategy
  /// @param token asset's token address
  /// @param tokenId asset's token ID
  /// @param amount Amount to deallocate
  /// @param data Data for strategy execution
  function deallocate(address token, uint256 tokenId, uint256 amount, bytes calldata data)
    external
    onlyAdminOrAutomator
  {
    AssetLib.Asset memory currentAsset = inventory.getAsset(token, tokenId);

    require(amount != 0, InvalidAssetAmount());
    require(currentAsset.amount >= amount, InvalidAssetAmount());
    require(currentAsset.strategy != address(0), InvalidAssetStrategy());

    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = AssetLib.Asset(currentAsset.assetType, currentAsset.strategy, token, tokenId, amount);

    _transferAsset(inputAssets[0], currentAsset.strategy);
    AssetLib.Asset[] memory returnAssets = IStrategy(currentAsset.strategy).convert(inputAssets, vaultConfig, data);
    _addAssets(returnAssets);

    emit Deallocate(inputAssets, returnAssets);
  }

  function harvest(AssetLib.Asset memory asset) external onlyAdminOrAutomator {
    require(asset.strategy != address(0), InvalidAssetStrategy());

    _harvest(asset);
  }

  function _harvest(AssetLib.Asset memory asset) internal {
    _transferAsset(asset, asset.strategy);
    AssetLib.Asset[] memory newAssets = IStrategy(asset.strategy).harvest(asset, vaultConfig.principalToken);
    _addAssets(newAssets);
  }

  /// @notice Returns the total value of the vault
  /// @return totalValue Total value of the vault in principal token
  function getTotalValue() public returns (uint256 totalValue) {
    totalValue = 0;
    AssetLib.Asset memory currentAsset;
    for (uint256 i = 0; i < inventory.assets.length;) {
      currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0)) {
        totalValue += IStrategy(currentAsset.strategy).valueOf(currentAsset, vaultConfig.principalToken);
      } else if (currentAsset.token == vaultConfig.principalToken) {
        totalValue += currentAsset.amount;
      }
      unchecked {
        i++;
      }
    }

    return totalValue;
  }

  /// @notice Returns the asset allocations of the vault
  /// @return assets Asset allocations of the vault
  function getAssetAllocations() external override returns (AssetLib.Asset[] memory assets) {
    /*
    Asset[] memory tempAssets = new Asset[](tokenAddresses.length() * 10); // Overestimate size
    uint256 index = 0;

    for (uint256 i = 0; i < inventory.assets.length; ) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];

      if (currentAsset.strategy != address(0)) {
    AssetLib.Asset[] memory strategyAssets = IStrategy(currentAsset.strategy).valueOf(currentAsset);
        for (uint256 k = 0; k < strategyAssets.length; ) {
          tempAssets[index] = strategyAssets[k];

          unchecked {
            index++;
            k++;
          }
        }
      } else {
        tempAssets[index] = currentAsset;

        unchecked {
          index++;
        }
      }

      unchecked {
        i++;
      }
    }

    // Create the exact-sized array and copy the results
    assets = new AssetLib.Asset[](index);
    for (uint256 i = 0; i < index; ) {
      assets[i] = tempAssets[i];

      unchecked {
        i++;
      }
    }
    */
  }

  /// @notice Sweeps the tokens to the caller
  /// @param tokens Tokens to sweep
  function sweepToken(address[] memory tokens) external nonReentrant onlyAdminOrAutomator {
    for (uint256 i = 0; i < tokens.length;) {
      IERC20 token = IERC20(tokens[i]);
      require(!inventory.contains(tokens[i], 0), InvalidSweepAsset());
      token.safeTransfer(_msgSender(), token.balanceOf(address(this)));

      unchecked {
        i++;
      }
    }

    emit SweepToken(tokens);
  }

  /// @notice Sweeps the non-fungible tokens to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  function sweepNFTToken(address[] memory _tokens, uint256[] memory _tokenIds)
    external
    nonReentrant
    onlyAdminOrAutomator
  {
    for (uint256 i = 0; i < _tokens.length;) {
      IERC721 token = IERC721(_tokens[i]);
      require(!inventory.contains(_tokens[i], _tokenIds[i]), InvalidSweepAsset());
      token.safeTransferFrom(address(this), _msgSender(), _tokenIds[i]);

      unchecked {
        i++;
      }
    }

    emit SweepNFToken(_tokens, _tokenIds);
  }

  /// @notice grant admin role to the address
  /// @param _address The address to which the admin role is granted
  function grantAdminRole(address _address) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(ADMIN_ROLE_HASH, _address);
  }

  /// @notice revoke admin role from the address
  /// @param _address The address from which the admin role is revoked
  function revokeAdminRole(address _address) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(ADMIN_ROLE_HASH, _address);
  }

  /// @notice Turn on allow deposit
  /// @param _config New vault config
  function allowDeposit(VaultConfig memory _config) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    require(!vaultConfig.allowDeposit && _config.allowDeposit, InvalidVaultConfig());
    require(vaultConfig.principalToken == _config.principalToken, InvalidVaultConfig());

    for (uint256 i = 0; i < inventory.assets.length; i++) {
      if (inventory.assets[i].strategy != address(0)) {
        IStrategy(inventory.assets[i].strategy).revalidate(inventory.assets[i], vaultConfig);
      }
    }

    vaultConfig = _config;

    emit SetVaultConfig(_config);
  }

  /// @dev Adds multiple assets to the vault
  /// @param newAssets New assets to add
  function _addAssets(AssetLib.Asset[] memory newAssets) internal {
    for (uint256 i = 0; i < newAssets.length;) {
      inventory.addAsset(newAssets[i]);

      unchecked {
        i++;
      }
    }
  }

  function _transferAssets(AssetLib.Asset[] memory assets, address to) internal {
    for (uint256 i = 0; i < assets.length;) {
      _transferAsset(assets[i], to);

      unchecked {
        i++;
      }
    }
  }

  /// @dev Transfers the asset to the recipient
  /// @param asset AssetLib.Asset to transfer
  /// @param to Recipient of the asset
  function _transferAsset(AssetLib.Asset memory asset, address to) internal {
    inventory.removeAsset(asset);
    if (asset.assetType == AssetLib.AssetType.ERC20) {
      IERC20(asset.token).safeTransfer(to, asset.amount);
    } else if (asset.assetType == AssetLib.AssetType.ERC721) {
      IERC721(asset.token).safeTransferFrom(address(this), to, asset.tokenId);
    }
  }

  function getInventory() external view returns (AssetLib.Asset[] memory assets) {
    return inventory.assets;
  }

  function getVaultConfig()
    external
    view
    override
    returns (
      bool isAllowDeposit,
      uint8 rangeStrategyType,
      uint8 tvlStrategyType,
      address principalToken,
      address[] memory supportedAddresses
    )
  {
    isAllowDeposit = vaultConfig.allowDeposit;
    rangeStrategyType = vaultConfig.rangeStrategyType;
    tvlStrategyType = vaultConfig.tvlStrategyType;
    principalToken = vaultConfig.principalToken;
    supportedAddresses = vaultConfig.supportedAddresses;
  }
}
