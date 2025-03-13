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
import "../interfaces/core/IWhitelistManager.sol";
import { AssetLib } from "../libraries/AssetLib.sol";
import { InventoryLib } from "../libraries/InventoryLib.sol";

contract Vault is AccessControlUpgradeable, ERC20PermitUpgradeable, ReentrancyGuard, IVault {
  using SafeERC20 for IERC20;

  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;
  using InventoryLib for InventoryLib.Inventory;

  uint256 public constant SHARES_PRECISION = 1e4;
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  IWhitelistManager public whitelistManager;

  address public override vaultOwner;
  address public principalToken;
  uint256 public principalTokenAmountMin;
  bool public allowDeposit;
  address[] public supportedTokens;

  InventoryLib.Inventory inventory;

  /// @notice Initializes the vault
  /// @param params Vault creation parameters
  /// @param _owner Owner of the vault
  /// @param _whitelistManager Address of the whitelist manager
  /// @param _vaultAutomator Address of the vault automator
  function initialize(
    VaultCreateParams memory params,
    address _owner,
    address _whitelistManager,
    address _vaultAutomator
  ) public initializer {
    require(params.principalToken != address(0), ZeroAddress());
    require(_whitelistManager != address(0), ZeroAddress());

    __ERC20_init(params.name, params.symbol);
    __ERC20Permit_init(params.name);
    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(ADMIN_ROLE_HASH, _owner);
    _grantRole(ADMIN_ROLE_HASH, _vaultAutomator);

    whitelistManager = IWhitelistManager(_whitelistManager);
    vaultOwner = _owner;
    principalToken = params.principalToken;
    principalTokenAmountMin = params.principalTokenAmountMin;
    allowDeposit = params.allowDeposit;
    supportedTokens = params.supportedTokens;
    AssetLib.Asset memory firstAsset = AssetLib.Asset(
      AssetLib.AssetType.ERC20,
      address(0),
      params.principalToken,
      0,
      params.principalTokenAmount
    );

    inventory.addAsset(firstAsset);
    _mint(_owner, params.principalTokenAmount * SHARES_PRECISION);

    emit Deposit(_owner, params.principalTokenAmount * SHARES_PRECISION);
  }

  /// @notice Deposits the asset to the vault
  /// @param shares Amount of shares to be minted
  /// @return returnShares Amount of shares minted
  function deposit(uint256 shares) external nonReentrant returns (uint256 returnShares) {
    require(allowDeposit || (!allowDeposit && _msgSender() == vaultOwner), DepositNotAllowed());

    uint256 totalSupply = totalSupply();

    for (uint256 i = 0; i < inventory.assets.length; ) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0)) _harvest(currentAsset);
      unchecked {
        i++;
      }
    }

    for (uint256 i = 0; i < inventory.assets.length; ) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];

      if (currentAsset.strategy != address(0)) {
        AssetLib.Asset[] memory underlyingAssets = IStrategy(currentAsset.strategy).getUnderlyingAssets(currentAsset);

        for (uint256 k = 0; k < underlyingAssets.length; ) {
          underlyingAssets[k].amount = (shares * underlyingAssets[k].amount) / totalSupply;
          IERC20(underlyingAssets[k].token).safeTransferFrom(
            _msgSender(),
            currentAsset.strategy,
            underlyingAssets[k].amount
          );

          unchecked {
            k++;
          }
        }

        _transferAsset(currentAsset, currentAsset.strategy);
        AssetLib.Asset[] memory newAssets = IStrategy(currentAsset.strategy).convertIntoExisting(
          currentAsset,
          underlyingAssets
        );
        _addAssets(newAssets);
      }
      unchecked {
        i++;
      }
    }

    for (uint256 i = 0; i < inventory.assets.length; ) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy == address(0) && currentAsset.assetType == AssetLib.AssetType.ERC20) {
        uint256 amount = (shares * currentAsset.amount) / totalSupply;

        IERC20(currentAsset.token).safeTransferFrom(_msgSender(), address(this), amount);
        currentAsset.amount += amount;
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
  function withdraw(uint256 shares) external nonReentrant {}

  /// @notice Allocates un-used assets to the strategy
  /// @param inputAssets Input assets to allocate
  /// @param strategy Strategy to allocate to
  /// @param data Data for the strategy
  function allocate(
    AssetLib.Asset[] memory inputAssets,
    IStrategy strategy,
    bytes calldata data
  ) external onlyRole(ADMIN_ROLE_HASH) {
    require(whitelistManager.isWhitelistedStrategy(address(strategy)), InvalidStrategy());

    if (supportedTokens.length != 0) {
      for (uint256 i = 0; i < inputAssets.length; ) {
        if (inputAssets[i].assetType == AssetLib.AssetType.ERC20) {
          require(_isSupportedToken(inputAssets[i].token), InvalidAssetToken());
        }

        unchecked {
          i++;
        }
      }
    }

    AssetLib.Asset memory currentAsset;

    for (uint256 i = 0; i < inputAssets.length; ) {
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

    AssetLib.Asset[] memory newAssets = strategy.convert(inputAssets, principalTokenAmountMin, data);

    _addAssets(newAssets);

    emit Allocate(inputAssets, strategy, newAssets);
  }

  /// @notice Deallocates the assets from the strategy
  /// @param token asset's token address
  /// @param tokenId asset's token ID
  /// @param amount Amount to deallocate
  /// @param data Data for strategy execution
  function deallocate(
    address token,
    uint256 tokenId,
    uint256 amount,
    bytes calldata data
  ) external onlyRole(ADMIN_ROLE_HASH) {
    AssetLib.Asset memory currentAsset = inventory.getAsset(token, tokenId);

    require(amount != 0, InvalidAssetAmount());
    require(currentAsset.amount >= amount, InvalidAssetAmount());
    require(currentAsset.strategy != address(0), InvalidAssetStrategy());

    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = AssetLib.Asset(currentAsset.assetType, currentAsset.strategy, token, tokenId, amount);

    _transferAsset(inputAssets[0], currentAsset.strategy);

    AssetLib.Asset[] memory returnAssets = IStrategy(currentAsset.strategy).convert(
      inputAssets,
      principalTokenAmountMin,
      data
    );

    _addAssets(returnAssets);

    emit Deallocate(inputAssets, returnAssets);
  }

  function harvest(AssetLib.Asset memory asset) external onlyRole(ADMIN_ROLE_HASH) {
    _harvest(asset);
  }

  function _harvest(AssetLib.Asset memory asset) internal {
    require(asset.strategy != address(0), InvalidAssetStrategy());

    _transferAsset(asset, asset.strategy);
    AssetLib.Asset[] memory newAssets = IStrategy(asset.strategy).harvest(asset);
    _addAssets(newAssets);
  }

  /// @notice Returns the total value of the vault
  /// @return value Total value of the vault in principal token
  function getTotalValue() external returns (uint256 value) {}

  /// @notice Returns the asset allocations of the vault
  /// @return assets AssetLib.Asset allocations of the vault
  function getAssetAllocations() external override returns (AssetLib.Asset[] memory assets) {
    AssetLib.Asset[] memory tempAssets = new AssetLib.Asset[](inventory.assets.length * 10); // Overestimate size
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
  }

  /// @notice Sweeps the tokens to the caller
  /// @param tokens Tokens to sweep
  function sweepToken(address[] memory tokens) external nonReentrant onlyRole(ADMIN_ROLE_HASH) {
    for (uint256 i = 0; i < tokens.length; ) {
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
  function sweepNFTToken(
    address[] memory _tokens,
    uint256[] memory _tokenIds
  ) external nonReentrant onlyRole(ADMIN_ROLE_HASH) {
    for (uint256 i = 0; i < _tokens.length; ) {
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

  /// @notice Sets the allow deposit flag
  /// @param _allowDeposit Allow deposit flag
  function setAllowDeposit(bool _allowDeposit) external override onlyRole(ADMIN_ROLE_HASH) {
    allowDeposit = _allowDeposit;
    emit SetAllowDeposit(_allowDeposit);
  }

  /// @dev Adds multiple assets to the vault
  /// @param newAssets New assets to add
  function _addAssets(AssetLib.Asset[] memory newAssets) internal {
    for (uint256 i = 0; i < newAssets.length; ) {
      inventory.addAsset(newAssets[i]);

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

  /// @dev Checks if the token is supported
  /// @param token Token to check
  /// @return bool True if the token is supported
  function _isSupportedToken(address token) internal view returns (bool) {
    for (uint256 i = 0; i < supportedTokens.length; ) {
      if (supportedTokens[i] == token) {
        return true;
      }

      unchecked {
        i++;
      }
    }

    return false;
  }

  function getInventory() external view returns (AssetLib.Asset[] memory assets) {
    return inventory.assets;
  }
}
