// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./CustomEIP712.sol";
import "../../interfaces/core/IVaultAutomator.sol";
import "../../interfaces/strategies/ILpStrategy.sol";

contract VaultAutomator is CustomEIP712, AccessControl, Pausable, IVaultAutomator {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner) CustomEIP712("V3AutomationOrder", "4.0") {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
  }

  /// @notice Execute an allocate on a Vault
  /// @param vault Vault
  /// @param inputAssets Input assets
  /// @param strategy Strategy
  /// @param allocateData allocateData data to be passed to vault's allocate function
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeAllocate(
    IVault vault,
    AssetLib.Asset[] memory inputAssets,
    IStrategy strategy,
    uint16 gasFeeBasisPoint,
    bytes calldata allocateData,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateOrder(abiEncodedUserOrder, orderSignature, vault.vaultOwner());
    Instruction memory instruction = abi.decode(allocateData, (Instruction));
    require(
      instruction.instructionType == uint8(ILpStrategy.InstructionType.SwapAndRebalancePosition)
        || instruction.instructionType == uint8(ILpStrategy.InstructionType.SwapAndCompound)
        || instruction.instructionType == uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      InvalidInstructionType()
    );
    vault.allocate(inputAssets, strategy, gasFeeBasisPoint, allocateData);
  }

  /// @notice Execute sweep token
  /// @param vault Vault address
  /// @param tokens Tokens to sweep
  function executeSweepToken(IVault vault, address[] memory tokens) external override onlyRole(OPERATOR_ROLE_HASH) {
    vault.sweepToken(tokens);
  }

  /// @notice Execute sweep NFT token ERC721
  /// @param vault Vault address
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  function executeSweepERC721(IVault vault, address[] memory tokens, uint256[] memory tokenIds)
    external
    override
    onlyRole(OPERATOR_ROLE_HASH)
  {
    vault.sweepERC721(tokens, tokenIds);
  }

  /// @notice Execute sweep NFT token ERC1155
  /// @param vault Vault address
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  /// @param amounts Amounts to sweep
  function executeSweepERC1155(
    IVault vault,
    address[] memory tokens,
    uint256[] memory tokenIds,
    uint256[] memory amounts
  ) external override onlyRole(OPERATOR_ROLE_HASH) {
    vault.sweepERC1155(tokens, tokenIds, amounts);
  }

  /// @dev Validate the order
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  /// @param actor Actor of the order
  function _validateOrder(bytes memory abiEncodedUserOrder, bytes memory orderSignature, address actor) internal view {
    address userAddress = _recover(abiEncodedUserOrder, orderSignature);
    require(userAddress == actor, InvalidSignature());
    require(!_cancelledOrder[keccak256(orderSignature)], OrderCancelled());
  }

  /// @notice Cancel an order
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function cancelOrder(bytes calldata abiEncodedUserOrder, bytes calldata orderSignature) external {
    _validateOrder(abiEncodedUserOrder, orderSignature, msg.sender);
    _cancelledOrder[keccak256(orderSignature)] = true;
    emit CancelOrder(msg.sender, abiEncodedUserOrder, orderSignature);
  }

  /// @notice Check if an order is cancelled
  /// @param orderSignature Signature of the order
  /// @return true if the order is cancelled
  function isOrderCancelled(bytes calldata orderSignature) external view returns (bool) {
    return _cancelledOrder[keccak256(orderSignature)];
  }

  /// @notice Grant operator role
  /// @param operator Operator address
  function grantOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @notice Revoke operator role
  /// @param operator Operator address
  function revokeOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(OPERATOR_ROLE_HASH, operator);
  }

  receive() external payable { }
}
