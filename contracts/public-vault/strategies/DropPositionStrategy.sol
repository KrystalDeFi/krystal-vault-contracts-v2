// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../interfaces/core/IConfigManager.sol";
import "../interfaces/strategies/IStrategy.sol";
import "../libraries/AssetLib.sol";

interface IOperatorVault {
  function operator() external view returns (address);
}

/// @notice Emergency public-vault strategy for removing an NFT position from vault accounting.
/// @dev Intended to be called through Vault.allocate via delegatecall.
contract DropPositionStrategy is IStrategy {
  enum InstructionType {
    DropPosition,
    RecoverPosition
  }

  struct RecoverPositionParams {
    address nfpm;
    uint256 tokenId;
    address strategy;
  }

  event PositionDropped(address indexed vault, address indexed operator, address indexed nfpm, uint256 tokenId);

  event PositionRecovered(address indexed vault, address indexed operator, address indexed nfpm, uint256 tokenId);

  error Unauthorized();

  IConfigManager public immutable configManager;

  constructor(address _configManager) {
    require(_configManager != address(0), ZeroAddress());
    configManager = IConfigManager(_configManager);
  }

  function valueOf(AssetLib.Asset calldata, address) external pure returns (uint256) {
    return 0;
  }

  function convert(AssetLib.Asset[] calldata assets, VaultConfig calldata, FeeConfig calldata, bytes calldata data)
    external
    payable
    returns (AssetLib.Asset[] memory returnAssets)
  {
    Instruction memory instruction = abi.decode(data, (Instruction));

    if (instruction.instructionType == uint8(InstructionType.DropPosition)) return _dropPosition(assets);

    if (instruction.instructionType == uint8(InstructionType.RecoverPosition)) {
      return _recoverPosition(assets, abi.decode(instruction.params, (RecoverPositionParams)));
    }

    revert InvalidInstructionType();
  }

  function harvest(AssetLib.Asset calldata, address, uint256, VaultConfig calldata, FeeConfig calldata)
    external
    payable
    returns (AssetLib.Asset[] memory)
  {
    revert InvalidInstructionType();
  }

  function convertFromPrincipal(AssetLib.Asset calldata, uint256, VaultConfig calldata)
    external
    payable
    returns (AssetLib.Asset[] memory)
  {
    revert InvalidInstructionType();
  }

  function convertToPrincipal(AssetLib.Asset memory, uint256, uint256, VaultConfig calldata, FeeConfig calldata)
    external
    payable
    returns (AssetLib.Asset[] memory)
  {
    revert InvalidInstructionType();
  }

  function revalidate(AssetLib.Asset calldata, VaultConfig calldata) external pure {
    revert InvalidInstructionType();
  }

  function _dropPosition(AssetLib.Asset[] calldata assets) internal returns (AssetLib.Asset[] memory returnAssets) {
    require(assets.length == 1, InvalidNumberOfAssets());

    AssetLib.Asset calldata asset = assets[0];
    require(asset.assetType == AssetLib.AssetType.ERC721 && asset.amount == 1, InvalidAsset());

    address operator = IOperatorVault(address(this)).operator();
    require(operator != address(0), ZeroAddress());
    require(IERC721(asset.token).ownerOf(asset.tokenId) == address(this), InvalidAsset());

    IERC721(asset.token).safeTransferFrom(address(this), operator, asset.tokenId);

    emit PositionDropped(address(this), operator, asset.token, asset.tokenId);
    return new AssetLib.Asset[](0);
  }

  function _recoverPosition(AssetLib.Asset[] calldata assets, RecoverPositionParams memory params)
    internal
    returns (AssetLib.Asset[] memory returnAssets)
  {
    require(assets.length == 0, InvalidNumberOfAssets());
    require(params.nfpm != address(0) && params.strategy != address(0), ZeroAddress());
    require(configManager.isWhitelistedStrategy(params.strategy), InvalidStrategy());

    address operator = IOperatorVault(address(this)).operator();
    require(operator != address(0), ZeroAddress());
    require(msg.sender == operator, Unauthorized());
    require(IERC721(params.nfpm).ownerOf(params.tokenId) == operator, InvalidAsset());

    IERC721(params.nfpm).safeTransferFrom(operator, address(this), params.tokenId);
    require(IERC721(params.nfpm).ownerOf(params.tokenId) == address(this), InvalidAsset());

    returnAssets = new AssetLib.Asset[](1);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC721, params.strategy, params.nfpm, params.tokenId, 1);

    emit PositionRecovered(address(this), operator, params.nfpm, params.tokenId);
  }
}
