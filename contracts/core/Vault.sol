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

contract Vault is AccessControlUpgradeable, ERC20PermitUpgradeable, ReentrancyGuard, IVault {
  using SafeERC20 for IERC20;

  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;

  uint256 public constant SHARES_PRECISION = 1e4;
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  IWhitelistManager public whitelistManager;

  address public override vaultOwner;
  address public principalToken;

  EnumerableSet.AddressSet private tokenAddresses;
  mapping(address => EnumerableSet.UintSet) private tokenIndices;
  mapping(address => mapping(uint256 => Asset)) public currentAssets;

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
    Asset memory firstAsset =
      Asset(AssetType.ERC20, address(0), params.principalToken, 0, params.principalTokenAmount);

    _addAsset(firstAsset);
    _mint(_owner, params.principalTokenAmount * SHARES_PRECISION);

    emit Deposit(_owner, params.principalTokenAmount * SHARES_PRECISION);
  }

  /// @notice Deposits the asset to the vault
  /// @param shares Amount of shares to be minted
  /// @return returnShares Amount of shares minted
  function deposit(uint256 shares) external nonReentrant returns (uint256 returnShares) {
    uint256 totalSupply = totalSupply();
    for (uint256 i = 0; i < tokenAddresses.length();) {
      address token = tokenAddresses.at(i);

      for (uint256 j = 0; j < tokenIndices[token].length();) {
        uint256 tokenId = tokenIndices[token].at(j);
        Asset memory currentAsset = currentAssets[token][tokenId];
        if (currentAsset.strategy != address(0)) _harvest(currentAsset);
        unchecked {
          j++;
        }
      }
      unchecked {
        i++;
      }
    }

    for (uint256 i = 0; i < tokenAddresses.length();) {
      address token = tokenAddresses.at(i);
      for (uint256 j = 0; j < tokenIndices[token].length();) {
        uint256 tokenId = tokenIndices[token].at(j);
        Asset memory currentAsset = currentAssets[token][tokenId];

        if (currentAsset.strategy != address(0)) {
          Asset[] memory underlyingAssets =
            IStrategy(currentAsset.strategy).getUnderlyingAssets(currentAsset);

          for (uint256 k = 0; k < underlyingAssets.length;) {
            underlyingAssets[k].amount = (shares * underlyingAssets[k].amount) / totalSupply;
            IERC20(underlyingAssets[k].token).safeTransferFrom(
              _msgSender(), currentAsset.strategy, underlyingAssets[k].amount
            );

            unchecked {
              k++;
            }
          }

          _transferAsset(currentAsset, currentAsset.strategy);
          Asset[] memory newAssets =
            IStrategy(currentAsset.strategy).convertIntoExisting(currentAsset, underlyingAssets);
          _addAssets(newAssets);
        }
        unchecked {
          j++;
        }
      }
      unchecked {
        i++;
      }
    }

    for (uint256 i = 0; i < tokenAddresses.length();) {
      address token = tokenAddresses.at(i);

      for (uint256 j = 0; j < tokenIndices[token].length();) {
        uint256 tokenId = tokenIndices[token].at(j);
        Asset memory currentAsset = currentAssets[token][tokenId];
        if (currentAsset.strategy == address(0) && currentAsset.assetType == AssetType.ERC20) {
          uint256 amount = (shares * currentAsset.amount) / totalSupply;

          IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);
          currentAsset.amount += amount;
        }
        unchecked {
          j++;
        }
      }
      unchecked {
        i++;
      }
    }

    _mint(_msgSender(), shares);

    emit Deposit(_msgSender(), shares);

    return shares;
  }

  /// @notice Allocates un-used assets to the strategy
  /// @param inputAssets Input assets to allocate
  /// @param strategy Strategy to allocate to
  /// @param data Data for the strategy
  function allocate(Asset[] memory inputAssets, IStrategy strategy, bytes calldata data)
    external
    onlyRole(ADMIN_ROLE_HASH)
  {
    require(whitelistManager.isWhitelisted(address(strategy)), InvalidStrategy());

    Asset memory currentAsset;

    for (uint256 i = 0; i < inputAssets.length;) {
      require(inputAssets[i].amount != 0, InvalidAssetAmount());

      currentAsset = currentAssets[inputAssets[i].token][inputAssets[i].tokenId];

      require(currentAsset.amount >= inputAssets[i].amount, InvalidAssetAmount());
      // Only allow allocation to a strategy if the asset is not already allocated and is ERC20
      require(currentAsset.strategy == address(0), InvalidAssetStrategy());
      require(currentAsset.assetType == AssetType.ERC20, InvalidAssetType());

      currentAsset.amount -= inputAssets[i].amount;

      currentAssets[currentAsset.token][currentAsset.tokenId] = currentAsset;
      inputAssets[i].strategy = currentAsset.strategy;

      _transferAsset(inputAssets[i], address(strategy));

      unchecked {
        i++;
      }
    }

    Asset[] memory newAssets = strategy.convert(inputAssets, data);

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
    onlyRole(ADMIN_ROLE_HASH)
  {
    Asset memory currentAsset = currentAssets[token][tokenId];

    require(amount != 0, InvalidAssetAmount());
    require(currentAsset.amount >= amount, InvalidAssetAmount());
    require(currentAsset.strategy != address(0), InvalidAssetStrategy());

    Asset[] memory inputAssets = new Asset[](1);
    inputAssets[0] = Asset(currentAsset.assetType, currentAsset.strategy, token, tokenId, amount);

    _transferAsset(inputAssets[0], currentAsset.strategy);

    Asset[] memory returnAssets = IStrategy(currentAsset.strategy).convert(inputAssets, data);

    _addAssets(returnAssets);

    emit Deallocate(inputAssets, returnAssets);
  }

  function harvest(Asset memory asset) external onlyRole(ADMIN_ROLE_HASH) {
    _harvest(asset);
  }

  function _harvest(Asset memory asset) internal {
    require(asset.strategy != address(0), InvalidAssetStrategy());

    _transferAsset(asset, asset.strategy);
    Asset[] memory newAssets = IStrategy(asset.strategy).harvest(asset);
    _addAssets(newAssets);
  }

  /// @notice Returns the total value of the vault
  /// @return value Total value of the vault in principal token
  function getTotalValue() external returns (uint256 value) {}

  /// @notice Returns the asset allocations of the vault
  /// @return assets Asset allocations of the vault
  /// @return values Asset values of the vault
  function getAssetAllocations() external returns (Asset[] memory assets, uint256[] memory values) {}

  /// @notice Sweeps the tokens to the caller
  /// @param tokens Tokens to sweep
  function sweepToken(address[] memory tokens) external nonReentrant onlyRole(ADMIN_ROLE_HASH) {
    for (uint256 i = 0; i < tokens.length;) {
      IERC20 token = IERC20(tokens[i]);
      require(!tokenAddresses.contains(tokens[i]), InvalidSweepAsset());
      token.safeTransfer(_msgSender(), token.balanceOf(address(this)));

      unchecked {
        i++;
      }
    }

    emit SweepToken(tokens);
  }

  /// @notice Sweeps the non-fungible tokens to the caller
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  function sweepNFTToken(address[] memory tokens, uint256[] memory tokenIds)
    external
    nonReentrant
    onlyRole(ADMIN_ROLE_HASH)
  {
    for (uint256 i = 0; i < tokens.length;) {
      IERC721 token = IERC721(tokens[i]);
      require(
        !tokenAddresses.contains(tokens[i]) && !tokenIndices[tokens[i]].contains(tokenIds[i]),
        InvalidSweepAsset()
      );
      token.safeTransferFrom(address(this), _msgSender(), tokenIds[i]);

      unchecked {
        i++;
      }
    }

    emit SweepNFToken(tokens, tokenIds);
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

  /// @dev Adds multiple assets to the vault
  /// @param newAssets New assets to add
  function _addAssets(Asset[] memory newAssets) internal {
    for (uint256 i = 0; i < newAssets.length;) {
      _addAsset(newAssets[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @dev Adds an asset to the vault
  /// @param asset Asset to add
  function _addAsset(Asset memory asset) internal {
    Asset memory currentAsset = currentAssets[asset.token][asset.tokenId];

    currentAsset.amount += asset.amount;
    currentAssets[asset.token][asset.tokenId] = currentAsset;

    tokenAddresses.add(asset.token);
    tokenIndices[asset.token].add(asset.tokenId);
  }

  /// @dev Transfers the asset to the recipient
  /// @param asset Asset to transfer
  /// @param to Recipient of the asset
  function _transferAsset(Asset memory asset, address to) internal {
    Asset memory currentAsset = currentAssets[asset.token][asset.tokenId];

    currentAsset.amount -= asset.amount;

    currentAssets[asset.token][asset.tokenId] = currentAsset;

    if (asset.assetType == AssetType.ERC20) {
      IERC20(asset.token).safeTransfer(to, asset.amount);
    } else if (asset.assetType == AssetType.ERC721) {
      IERC721(asset.token).safeTransferFrom(address(this), to, asset.tokenId);
    }
  }
}
