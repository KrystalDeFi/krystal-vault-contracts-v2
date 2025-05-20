// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;
pragma abicoder v2;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import { AssetLib } from "../libraries/AssetLib.sol";
import { InventoryLib } from "../libraries/InventoryLib.sol";

import "../interfaces/strategies/IStrategy.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/core/IConfigManager.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { IVaultFactory } from "../interfaces/core/IVaultFactory.sol";

contract Vault is
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  ReentrancyGuard,
  ERC721Holder,
  ERC1155Holder,
  IVault
{
  using SafeERC20 for IERC20;
  using InventoryLib for InventoryLib.Inventory;

  uint256 public constant SHARES_PRECISION = 1e4;
  uint16 public constant WITHDRAWAL_FEE = 10; // 0.1%
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  IConfigManager public configManager;

  address public override vaultOwner;
  address public override WETH;
  address public vaultFactory;
  VaultConfig private vaultConfig;

  InventoryLib.Inventory private inventory;
  uint256 lastAllocateBlockNumber;

  modifier onlyAutomator() {
    require(configManager.isWhitelistedAutomator(_msgSender()), Unauthorized());
    _;
  }

  modifier onlyAdminOrAutomator() {
    require(
      hasRole(ADMIN_ROLE_HASH, _msgSender()) || configManager.isWhitelistedAutomator(_msgSender()), Unauthorized()
    );
    _;
  }

  modifier whenNotPaused() {
    require(!configManager.isVaultPaused(), VaultPaused());
    _;
  }

  /// @notice Initializes the vault
  /// @param params Vault creation parameters
  /// @param _owner Owner of the vault
  /// @param _configManager Address of the whitelist manager
  /// @param _weth Address of the WETH token
  function initialize(VaultCreateParams calldata params, address _owner, address _configManager, address _weth)
    public
    initializer
  {
    require(params.config.principalToken != address(0), ZeroAddress());
    require(_configManager != address(0), ZeroAddress());

    // Initialize ERC20 and Access Control
    __ERC20_init(params.name, params.symbol);
    __ERC20Permit_init(params.name);
    __AccessControl_init();

    // Grant roles to owner
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(ADMIN_ROLE_HASH, _owner);

    // Cache variables to minimize storage writes
    configManager = IConfigManager(_configManager);
    vaultOwner = _owner;
    vaultFactory = _msgSender();
    WETH = _weth;
    vaultConfig = params.config;

    uint256 principalAmount = params.principalTokenAmount;
    address principalToken = params.config.principalToken;

    // Initialize first asset in inventory
    inventory.addAsset(AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), principalToken, 0, principalAmount));

    // Mint shares only if principalAmount > 0 to save gas on unnecessary operations
    if (principalAmount > 0) {
      unchecked {
        uint256 mintAmount = principalAmount * SHARES_PRECISION;
        _mint(_owner, mintAmount);
        emit VaultDeposit(_msgSender(), _owner, principalAmount, mintAmount);
      }
    }
  }

  /// @notice Deposits the asset to the vault
  /// @param principalAmount Amount of in principalToken
  /// @param minShares Minimum amount of shares to mint
  /// @return shares Amount of shares minted
  function deposit(uint256 principalAmount, uint256 minShares)
    external
    payable
    nonReentrant
    whenNotPaused
    returns (uint256 shares)
  {
    require(_msgSender() == vaultOwner || vaultConfig.allowDeposit, DepositNotAllowed());
    require(principalAmount != 0, InvalidAssetAmount());

    uint256 length = inventory.assets.length;

    for (uint256 i; i < length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) _harvest(currentAsset, 0);

      unchecked {
        i++;
      }
    }
    address principalToken = vaultConfig.principalToken;
    uint256 totalValue = getTotalValue();

    if (msg.value > 0) {
      require(principalToken == WETH, InvalidAssetToken());
      require(principalAmount == msg.value, InvalidAssetAmount());
      IWETH9(principalToken).deposit{ value: msg.value }();
    } else {
      IERC20(principalToken).safeTransferFrom(_msgSender(), address(this), principalAmount);
    }

    inventory.addAsset(AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), principalToken, 0, principalAmount));

    for (uint256 i; i < inventory.assets.length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];

      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) {
        uint256 strategyPosValue = IStrategy(currentAsset.strategy).valueOf(currentAsset, principalToken);
        if (strategyPosValue != 0) {
          uint256 pAmountForStrategy = FullMath.mulDiv(principalAmount, strategyPosValue, totalValue);
          inventory.removeAsset(currentAsset);
          inventory.removeAsset(
            AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), principalToken, 0, pAmountForStrategy)
          );
          bytes memory cData = abi.encodeWithSelector(
            IStrategy.convertFromPrincipal.selector, currentAsset, pAmountForStrategy, vaultConfig
          );
          bytes memory returnData = _delegateCallToStrategy(currentAsset.strategy, cData);
          _addAssets(abi.decode(returnData, (AssetLib.Asset[])));
        }
      }

      unchecked {
        i++;
      }
    }

    uint256 totalSupply = totalSupply();
    // update total value after distributing the principal amount to the strategies
    totalValue = getTotalValue() - principalAmount;

    shares =
      totalSupply == 0 ? principalAmount * SHARES_PRECISION : FullMath.mulDiv(principalAmount, totalSupply, totalValue);

    require(shares >= minShares, InsufficientShares());
    _mint(_msgSender(), shares);

    emit VaultDeposit(vaultFactory, _msgSender(), principalAmount, shares);

    return shares;
  }

  /// @notice Withdraws the asset as principal token from the vault
  /// @param shares Amount of shares to be burned
  /// @param unwrap Unwrap WETH to ETH
  /// @param minReturnAmount Minimum amount of principal token to return
  function withdraw(uint256 shares, bool unwrap, uint256 minReturnAmount) external nonReentrant {
    require(shares != 0, InvalidShares());
    uint256 currentTotalSupply = totalSupply();

    _burn(_msgSender(), shares);

    uint256 deductedShares =
      shares == currentTotalSupply ? shares : FullMath.mulDiv(shares, 10_000 - WITHDRAWAL_FEE, 10_000);

    FeeConfig memory feeConfig = configManager.getFeeConfig(vaultConfig.allowDeposit);
    feeConfig.vaultOwner = vaultOwner;

    uint256 returnAmount;
    address principalToken = vaultConfig.principalToken;
    uint256 length = inventory.assets.length;

    AssetLib.Asset[] memory assets;
    for (uint256 i; i < length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) _harvest(currentAsset, 0);
      unchecked {
        i++;
      }
    }

    length = inventory.assets.length;
    for (uint256 i; i < length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];

      if (
        currentAsset.strategy == address(0) && currentAsset.assetType == AssetLib.AssetType.ERC20
          && currentAsset.amount != 0
      ) {
        currentAsset.amount = FullMath.mulDiv(currentAsset.amount, deductedShares, currentTotalSupply);
        inventory.removeAsset(currentAsset);
        if (currentAsset.token == principalToken) returnAmount += currentAsset.amount;
        else IERC20(currentAsset.token).safeTransfer(_msgSender(), currentAsset.amount);
      }
      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) {
        inventory.removeAsset(currentAsset);
        bytes memory cData = abi.encodeWithSelector(
          IStrategy.convertToPrincipal.selector,
          currentAsset,
          deductedShares,
          currentTotalSupply,
          vaultConfig,
          feeConfig
        );
        bytes memory returnData = _delegateCallToStrategy(currentAsset.strategy, cData);
        // Decode the returned data
        assets = abi.decode(returnData, (AssetLib.Asset[]));
        for (uint256 k; k < assets.length;) {
          if (assets[k].assetType != AssetLib.AssetType.ERC20) inventory.addAsset(assets[k]);
          else if (assets[k].token == principalToken) returnAmount += assets[k].amount;
          else if (assets[k].amount > 0) IERC20(assets[k].token).safeTransfer(_msgSender(), assets[k].amount);
          unchecked {
            k++;
          }
        }
      }
      unchecked {
        i++;
      }
    }

    require(returnAmount >= minReturnAmount, InsufficientReturnAmount());

    if (unwrap && principalToken == WETH) {
      IWETH9(principalToken).withdraw(returnAmount);
      (bool sent,) = _msgSender().call{ value: returnAmount }("");
      require(sent, FailedToSendEther());
    } else {
      IERC20(principalToken).safeTransfer(_msgSender(), returnAmount);
    }

    if (totalSupply() == 0) {
      length = inventory.assets.length;
      for (; length > 0; length--) {
        inventory.removeAsset(0);
      }
    }

    emit VaultWithdraw(vaultFactory, _msgSender(), returnAmount, shares);
  }

  /// @notice Allocates un-used assets to the strategy
  /// @param inputAssets Input assets to allocate
  /// @param strategy Strategy to allocate to
  /// @param gasFeeX64 Gas fee with X64 precision
  /// @param data Data for the strategy
  function allocate(AssetLib.Asset[] calldata inputAssets, IStrategy strategy, uint64 gasFeeX64, bytes calldata data)
    external
    onlyAdminOrAutomator
    whenNotPaused
  {
    require(configManager.isWhitelistedStrategy(address(strategy)), InvalidStrategy());
    require(block.number > lastAllocateBlockNumber, ExceedMaxAllocatePerBlock());
    lastAllocateBlockNumber = block.number;

    AssetLib.Asset memory inputAsset;
    uint256 length = inputAssets.length;
    for (uint256 i; i < length;) {
      inputAsset = inputAssets[i];
      require(inputAsset.amount != 0, InvalidAssetAmount());

      inventory.removeAsset(inputAsset, true);

      unchecked {
        i++;
      }
    }

    FeeConfig memory feeConfig = configManager.getFeeConfig(vaultConfig.allowDeposit);
    feeConfig.gasFeeX64 = gasFeeX64;
    feeConfig.vaultOwner = vaultOwner;

    // Encode the function call parameters
    bytes memory cData = abi.encodeWithSelector(IStrategy.convert.selector, inputAssets, vaultConfig, feeConfig, data);
    bytes memory returnData = _delegateCallToStrategy(address(strategy), cData);

    // Decode the returned data
    AssetLib.Asset[] memory newAssets = abi.decode(returnData, (AssetLib.Asset[]));
    _addAssets(newAssets);

    // validate if number of assets that have strategy != address(0) < configManager.maxPositions
    uint8 strategyCount;
    length = inventory.assets.length;
    AssetLib.Asset memory currentAsset;

    for (uint256 i; i < length;) {
      currentAsset = inventory.assets[i];

      if (
        currentAsset.strategy != address(0)
          && IStrategy(currentAsset.strategy).valueOf(currentAsset, vaultConfig.principalToken) != 0
          && currentAsset.amount != 0
      ) strategyCount++;

      unchecked {
        i++;
      }
    }

    require(strategyCount < configManager.maxPositions(), MaxPositionsReached());

    emit VaultAllocate(vaultFactory, inputAssets, strategy, newAssets);
  }

  /// @notice Harvests the assets from the strategy
  /// @param asset Asset to harvest
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  function harvest(AssetLib.Asset calldata asset, uint256 amountTokenOutMin)
    external
    onlyAdminOrAutomator
    whenNotPaused
  {
    require(asset.strategy != address(0), InvalidAssetStrategy());

    AssetLib.Asset[] memory harvestedAssets = _harvest(asset, amountTokenOutMin);
    emit VaultHarvest(vaultFactory, harvestedAssets);
  }

  /// @dev Harvests the assets from the strategy
  /// @param asset Asset to harvest
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  /// @return harvestedAssets Harvested assets
  function _harvest(AssetLib.Asset memory asset, uint256 amountTokenOutMin)
    internal
    returns (AssetLib.Asset[] memory harvestedAssets)
  {
    inventory.removeAsset(asset);

    FeeConfig memory feeConfig = configManager.getFeeConfig(vaultConfig.allowDeposit);
    feeConfig.vaultOwner = vaultOwner;

    // Encode the function call parameters
    bytes memory data = abi.encodeWithSelector(
      IStrategy.harvest.selector, asset, vaultConfig.principalToken, amountTokenOutMin, vaultConfig, feeConfig
    );
    bytes memory returnData = _delegateCallToStrategy(asset.strategy, data);
    // Decode the returned data
    harvestedAssets = abi.decode(returnData, (AssetLib.Asset[]));
    _addAssets(harvestedAssets);
  }

  /// @notice Returns the total value of the vault
  /// @return totalValue Total value of the vault in principal token
  function getTotalValue() public view returns (uint256 totalValue) {
    uint256 length = inventory.assets.length;

    AssetLib.Asset memory currentAsset;

    for (uint256 i; i < length;) {
      currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) {
        totalValue += IStrategy(currentAsset.strategy).valueOf(currentAsset, vaultConfig.principalToken);
      } else if (currentAsset.token == vaultConfig.principalToken) {
        totalValue += currentAsset.amount;
      }

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweeps the tokens to the caller
  /// @param tokens Tokens to sweep
  function sweepToken(address[] calldata tokens) external nonReentrant onlyAutomator {
    uint256 length = tokens.length;

    for (uint256 i; i < length;) {
      require(!inventory.contains(tokens[i], 0), InvalidSweepAsset());
      IERC20 token = IERC20(tokens[i]);
      token.safeTransfer(_msgSender(), token.balanceOf(address(this)));

      unchecked {
        i++;
      }
    }

    emit SweepToken(tokens);
  }

  /// @notice Sweeps the non-fungible tokens ERC721 to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds) external nonReentrant onlyAutomator {
    uint256 length = _tokens.length;

    for (uint256 i; i < length;) {
      require(!inventory.contains(_tokens[i], _tokenIds[i]), InvalidSweepAsset());
      IERC721 token = IERC721(_tokens[i]);
      token.safeTransferFrom(address(this), _msgSender(), _tokenIds[i]);

      unchecked {
        i++;
      }
    }

    emit SweepERC721(_tokens, _tokenIds);
  }

  /// @notice Sweep ERC1155 tokens to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  /// @param _amounts Amounts to sweep
  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds, uint256[] calldata _amounts)
    external
    nonReentrant
    onlyAutomator
  {
    uint256 length = _tokens.length;

    for (uint256 i; i < length;) {
      require(!inventory.contains(_tokens[i], _tokenIds[i]), InvalidSweepAsset());
      IERC1155 token = IERC1155(_tokens[i]);
      token.safeTransferFrom(address(this), _msgSender(), _tokenIds[i], _amounts[i], "");

      unchecked {
        i++;
      }
    }

    emit SweepERC1155(_tokens, _tokenIds, _amounts);
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
  function allowDeposit(VaultConfig calldata _config) external override onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
    require(!vaultConfig.allowDeposit && _config.allowDeposit, InvalidVaultConfig());
    require(vaultConfig.principalToken == _config.principalToken, InvalidVaultConfig());

    uint256 length = inventory.assets.length;

    for (uint256 i; i < length;) {
      AssetLib.Asset memory asset = inventory.assets[i];
      if (asset.strategy != address(0) && asset.amount != 0) IStrategy(asset.strategy).revalidate(asset, _config);

      unchecked {
        i++;
      }
    }

    vaultConfig = _config;

    emit SetVaultConfig(vaultFactory, _config);
  }

  /// @dev Adds multiple assets to the vault
  /// @param newAssets New assets to add
  function _addAssets(AssetLib.Asset[] memory newAssets) internal {
    uint256 length = newAssets.length;

    for (uint256 i; i < length;) {
      inventory.addAsset(newAssets[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Returns the vault's inventory
  /// @return assets Array of assets in the vault
  function getInventory() external view returns (AssetLib.Asset[] memory assets) {
    return inventory.assets;
  }

  /// @notice Returns the vault's config
  /// @return isAllowDeposit Allow deposit
  /// @return rangeStrategyType Range strategy type
  /// @return tvlStrategyType TVL strategy type
  /// @return principalToken Principal token address
  /// @return supportedAddresses Supported addresses
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

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlUpgradeable, ERC1155Holder)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  receive() external payable {
    require(msg.sender == WETH, InvalidWETH());
  }

  function decimals() public view override returns (uint8) {
    return IERC20Metadata(vaultConfig.principalToken).decimals() + 4;
  }

  function _delegateCallToStrategy(address strategy, bytes memory cData) internal returns (bytes memory returnData) {
    bool success;
    (success, returnData) = strategy.delegatecall(cData);
    if (!success) {
      if (returnData.length == 0) revert("Strategy delegatecall failed");
      assembly {
        let returnDataSize := mload(returnData)
        revert(add(32, returnData), returnDataSize)
      }
    }
  }
}
