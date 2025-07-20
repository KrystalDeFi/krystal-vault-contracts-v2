// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

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
  uint16 public constant WITHDRAWAL_FEE = 1; // 0.01%
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  IConfigManager public configManager;

  address public override vaultOwner;
  uint16 public vaultOwnerFeeBasisPoint;
  address public operator;
  address public override WETH;
  address public vaultFactory;
  VaultConfig private vaultConfig;

  InventoryLib.Inventory private inventory;
  uint256 lastAllocateBlockNumber;

  modifier onlyOperator() {
    require(_msgSender() == operator, Unauthorized());
    _;
  }

  modifier onlyAdminOrAutomator() {
    require(
      hasRole(ADMIN_ROLE_HASH, _msgSender()) || configManager.isWhitelistedAutomator(_msgSender()), Unauthorized()
    );
    _;
  }

  modifier onlyPrivateVault() {
    require(!vaultConfig.allowDeposit, DepositAllowed());
    _;
  }

  modifier whenNotPaused() {
    require(!configManager.isVaultPaused(), VaultPaused());
    _;
  }

  /// @notice Initializes the vault
  /// @param params Vault creation parameters
  /// @param _owner Owner of the vault
  /// @param _operator Address of the operator
  /// @param _configManager Address of the whitelist manager
  /// @param _weth Address of the WETH token
  function initialize(
    VaultCreateParams calldata params,
    address _owner,
    address _operator,
    address _configManager,
    address _weth
  ) public initializer {
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
    vaultOwnerFeeBasisPoint = params.vaultOwnerFeeBasisPoint;
    operator = _operator;
    vaultFactory = _msgSender();
    WETH = _weth;
    vaultConfig = params.config;

    uint256 principalAmount = params.principalTokenAmount;

    // Initialize first asset in inventory
    inventory.addAsset(
      AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), params.config.principalToken, 0, principalAmount)
    );

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
    override
    nonReentrant
    whenNotPaused
    returns (uint256 shares)
  {
    require(_msgSender() == vaultOwner || vaultConfig.allowDeposit || principalAmount != 0, DepositNotAllowed());

    uint256 length = inventory.assets.length;

    for (uint256 i; i < length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) _harvest(currentAsset, 0, 0);

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
    uint256 newTotalValue = getTotalValue();
    if (newTotalValue - totalValue > principalAmount) {
      // The deposit of principalAmount make totalValue increases more than principalAmount
      totalValue = newTotalValue - principalAmount;
    }

    shares =
      totalSupply == 0 ? principalAmount * SHARES_PRECISION : FullMath.mulDiv(principalAmount, totalSupply, totalValue);

    require(shares >= minShares, InsufficientShares());
    _mint(_msgSender(), shares);

    emit VaultDeposit(vaultFactory, _msgSender(), principalAmount, shares);
  }

  /// @notice Deposits principal tokens for private vaults
  /// @param principalAmount Amount of principal tokens to deposit
  /// @return shares Amount of shares minted
  function depositPrincipal(uint256 principalAmount)
    external
    payable
    override
    nonReentrant
    onlyAdminOrAutomator
    onlyPrivateVault
    returns (uint256 shares)
  {
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

    uint256 totalSupply = totalSupply();

    shares =
      totalSupply == 0 ? principalAmount * SHARES_PRECISION : FullMath.mulDiv(principalAmount, totalSupply, totalValue);

    _mint(_msgSender(), shares);

    emit VaultDeposit(vaultFactory, _msgSender(), principalAmount, shares);
  }

  function getFeeConfig(uint64 gasFeeX64) internal view returns (FeeConfig memory feeConfig) {
    feeConfig = configManager.getFeeConfig(vaultConfig.allowDeposit);
    feeConfig.vaultOwner = vaultOwner;
    feeConfig.gasFeeX64 = gasFeeX64;
    feeConfig.vaultOwnerFeeBasisPoint = feeConfig.platformFeeBasisPoint + vaultOwnerFeeBasisPoint > 10_000
      ? 10_000 - feeConfig.platformFeeBasisPoint
      : vaultOwnerFeeBasisPoint;
  }

  /// @notice Withdraws the asset as principal token from the vault
  /// @param shares Amount of shares to be burned
  /// @param unwrap Unwrap WETH to ETH
  /// @param minReturnAmount Minimum amount of principal token to return
  /// @return returnAmount Amount of principal token returned
  function withdraw(uint256 shares, bool unwrap, uint256 minReturnAmount)
    external
    override
    nonReentrant
    returns (uint256 returnAmount)
  {
    uint256 currentTotalSupply = totalSupply();
    require(shares != 0 && shares <= currentTotalSupply, InvalidShares());

    _burn(_msgSender(), shares);

    uint256 deductedShares = shares;
    if (shares != currentTotalSupply && vaultConfig.allowDeposit) {
      deductedShares = FullMath.mulDiv(shares, 10_000 - WITHDRAWAL_FEE, 10_000);
    }

    FeeConfig memory feeConfig = getFeeConfig(0);

    address principalToken = vaultConfig.principalToken;
    uint256 length = inventory.assets.length;

    AssetLib.Asset[] memory assets;
    for (uint256 i; i < length;) {
      AssetLib.Asset memory currentAsset = inventory.assets[i];
      if (currentAsset.strategy != address(0) && currentAsset.amount != 0) _harvest(currentAsset, 0, 0);
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

  /// @notice Withdraws principal tokens (not from strategies) for private vaults
  /// @param amount Amount of principal tokens to withdraw
  /// @param unwrap Unwrap WETH to ETH
  /// @return returnAmount Amount of principal tokens returned
  function withdrawPrincipal(uint256 amount, bool unwrap)
    external
    override
    nonReentrant
    onlyAdminOrAutomator
    onlyPrivateVault
    returns (uint256)
  {
    // calculate shares to burn
    uint256 totalValue = getTotalValue();
    uint256 currentTotalSupply = totalSupply();
    uint256 shares = FullMath.mulDiv(currentTotalSupply, amount, totalValue);

    _burn(vaultOwner, shares);

    address principalToken = vaultConfig.principalToken;

    inventory.removeAsset(AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), principalToken, 0, amount));

    if (unwrap && principalToken == WETH) {
      IWETH9(principalToken).withdraw(amount);
      (bool sent,) = vaultOwner.call{ value: amount }("");
      require(sent, FailedToSendEther());
    } else {
      IERC20(principalToken).safeTransfer(vaultOwner, amount);
    }

    emit VaultWithdraw(vaultFactory, vaultOwner, amount, shares);

    return amount;
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
    for (uint256 i; i < inputAssets.length;) {
      inputAsset = inputAssets[i];
      require(inputAsset.amount != 0, InvalidAssetAmount());

      inventory.removeAsset(inputAsset, true);

      unchecked {
        i++;
      }
    }

    FeeConfig memory feeConfig = getFeeConfig(gasFeeX64);

    // Encode the function call parameters
    bytes memory cData = abi.encodeWithSelector(IStrategy.convert.selector, inputAssets, vaultConfig, feeConfig, data);
    bytes memory returnData = _delegateCallToStrategy(address(strategy), cData);

    // Decode the returned data
    AssetLib.Asset[] memory newAssets = abi.decode(returnData, (AssetLib.Asset[]));
    _addAssets(newAssets);

    // validate if number of assets that have strategy != address(0) < configManager.maxPositions
    uint8 strategyCount;
    AssetLib.Asset memory currentAsset;

    for (uint256 i; i < inventory.assets.length;) {
      currentAsset = inventory.assets[i];

      if (
        currentAsset.strategy != address(0)
          && IStrategy(currentAsset.strategy).valueOf(currentAsset, vaultConfig.principalToken) != 0
          && currentAsset.amount != 0
      ) {
        unchecked {
          strategyCount++;
        }
      }

      unchecked {
        i++;
      }
    }

    require(strategyCount < configManager.maxPositions(), MaxPositionsReached());

    emit VaultAllocate(vaultFactory, inputAssets, strategy, newAssets);
  }

  /// @notice Harvests the assets from the strategy
  /// @param asset Asset to harvest
  /// @param gasFeeX64 Gas fee with X64 precision
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  /// @return harvestedAssets Harvested assets
  function harvest(AssetLib.Asset calldata asset, uint64 gasFeeX64, uint256 amountTokenOutMin)
    external
    override
    onlyAdminOrAutomator
    whenNotPaused
    nonReentrant
    returns (AssetLib.Asset[] memory harvestedAssets)
  {
    require(asset.strategy != address(0), InvalidAssetStrategy());

    harvestedAssets = _harvest(asset, gasFeeX64, amountTokenOutMin);
    emit VaultHarvest(vaultFactory, harvestedAssets);
  }

  /// @notice Harvests rewards from a strategy asset and sends to vaultOwner (private vault only)
  /// @param assets Assets to harvest
  /// @param unwrap Unwrap WETH to ETH
  /// @param amountTokenOutMin Minimum amount out by tokenOut
  function harvestPrivate(AssetLib.Asset[] calldata assets, bool unwrap, uint64 gasFeeX64, uint256 amountTokenOutMin)
    external
    override
    nonReentrant
    onlyAdminOrAutomator
    onlyPrivateVault
  {
    address principalToken = vaultConfig.principalToken;
    uint256 principalHarvestedAmount;

    for (uint256 i; i < assets.length;) {
      AssetLib.Asset memory asset = assets[i];
      require(asset.strategy != address(0), InvalidAssetStrategy());

      // Harvest the asset
      AssetLib.Asset[] memory harvestedAssets = _harvest(asset, gasFeeX64, 0);

      // Process the harvested assets
      for (uint256 j; j < harvestedAssets.length;) {
        AssetLib.Asset memory ha = harvestedAssets[j];
        if (ha.assetType == AssetLib.AssetType.ERC20 && ha.amount > 0) {
          if (ha.token == principalToken) principalHarvestedAmount += ha.amount;
          else IERC20(ha.token).safeTransfer(vaultOwner, ha.amount);
          // Remove the asset because _harvest already added it to the inventory
          inventory.removeAsset(ha);
        }
        unchecked {
          j++;
        }
      }

      unchecked {
        i++;
      }
    }

    require(principalHarvestedAmount >= amountTokenOutMin, InsufficientReturnAmount());

    if (principalHarvestedAmount > 0) {
      if (unwrap && principalToken == WETH) {
        IWETH9(principalToken).withdraw(principalHarvestedAmount);
        (bool sent,) = _msgSender().call{ value: principalHarvestedAmount }("");
        require(sent, FailedToSendEther());
      } else {
        IERC20(principalToken).safeTransfer(vaultOwner, principalHarvestedAmount);
      }
    }

    emit VaultHarvestPrivate(vaultFactory, vaultOwner, principalHarvestedAmount);
  }

  /// @dev Harvests the assets from the strategy
  /// @param asset Asset to harvest
  /// @param amountTokenOutMin The minimum amount out by tokenOut
  /// @return harvestedAssets Harvested assets
  function _harvest(AssetLib.Asset memory asset, uint64 gasFeeX64, uint256 amountTokenOutMin)
    internal
    returns (AssetLib.Asset[] memory harvestedAssets)
  {
    inventory.removeAsset(asset);

    FeeConfig memory feeConfig = getFeeConfig(gasFeeX64);

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
  function sweepToken(address[] calldata tokens) external nonReentrant onlyOperator {
    for (uint256 i; i < tokens.length;) {
      IERC20 token = IERC20(tokens[i]);
      uint256 amount = token.balanceOf(address(this));
      if (inventory.contains(tokens[i], 0)) {
        AssetLib.Asset memory asset = inventory.getAsset(tokens[i], 0);
        amount -= asset.amount;
      }
      token.safeTransfer(_msgSender(), amount);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweeps the non-fungible tokens ERC721 to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds) external nonReentrant onlyOperator {
    for (uint256 i; i < _tokens.length;) {
      require(!inventory.contains(_tokens[i], _tokenIds[i]), InvalidSweepAsset());
      IERC721 token = IERC721(_tokens[i]);
      token.safeTransferFrom(address(this), _msgSender(), _tokenIds[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweep ERC1155 tokens to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds) external nonReentrant onlyOperator {
    for (uint256 i; i < _tokens.length;) {
      IERC1155 token = IERC1155(_tokens[i]);
      uint256 amount = token.balanceOf(address(this), _tokenIds[i]);
      if (inventory.contains(_tokens[i], _tokenIds[i])) {
        AssetLib.Asset memory asset = inventory.getAsset(_tokens[i], _tokenIds[i]);
        amount -= asset.amount;
      }
      token.safeTransferFrom(address(this), _msgSender(), _tokenIds[i], amount, "");

      unchecked {
        i++;
      }
    }
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
  /// @param _vaultOwnerFeeBasisPoint Vault owner fee basis point
  function allowDeposit(VaultConfig calldata _config, uint16 _vaultOwnerFeeBasisPoint)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    whenNotPaused
  {
    require(!vaultConfig.allowDeposit, InvalidVaultConfig());
    require(_config.allowDeposit, InvalidVaultConfig());
    require(vaultConfig.principalToken == _config.principalToken, InvalidVaultConfig());

    for (uint256 i; i < inventory.assets.length;) {
      AssetLib.Asset memory asset = inventory.assets[i];
      if (asset.strategy != address(0) && asset.amount != 0) IStrategy(asset.strategy).revalidate(asset, _config);

      unchecked {
        i++;
      }
    }

    vaultConfig = _config;
    vaultOwnerFeeBasisPoint = _vaultOwnerFeeBasisPoint;

    emit SetVaultConfig(vaultFactory, _config, _vaultOwnerFeeBasisPoint);
  }

  /// @notice Transfer ownership of the vault to a new owner
  /// @param newOwner New owner address
  function transferOwnership(address newOwner) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    require(newOwner != address(0), ZeroAddress());

    emit VaultOwnerChanged(vaultFactory, vaultOwner, newOwner);

    // Grant admin role to the new owner
    _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
    _grantRole(ADMIN_ROLE_HASH, newOwner);

    // Revoke admin role from the current owner
    _revokeRole(DEFAULT_ADMIN_ROLE, vaultOwner);
    _revokeRole(ADMIN_ROLE_HASH, vaultOwner);

    vaultOwner = newOwner;
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
  /// @return _vaultOwnerFeeBasisPoint Vault owner fee basis point
  function getVaultConfig()
    external
    view
    override
    returns (
      bool isAllowDeposit,
      uint8 rangeStrategyType,
      uint8 tvlStrategyType,
      address principalToken,
      address[] memory supportedAddresses,
      uint16 _vaultOwnerFeeBasisPoint
    )
  {
    isAllowDeposit = vaultConfig.allowDeposit;
    rangeStrategyType = vaultConfig.rangeStrategyType;
    tvlStrategyType = vaultConfig.tvlStrategyType;
    principalToken = vaultConfig.principalToken;
    supportedAddresses = vaultConfig.supportedAddresses;
    _vaultOwnerFeeBasisPoint = vaultOwnerFeeBasisPoint;
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

  function decimals() public view override returns (uint8) {
    return IERC20Metadata(vaultConfig.principalToken).decimals() + 4;
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

  function _delegateCallToStrategy(address strategy, bytes memory cData) internal returns (bytes memory returnData) {
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

  receive() external payable {
    require(msg.sender == WETH, InvalidWETH());
  }
}
