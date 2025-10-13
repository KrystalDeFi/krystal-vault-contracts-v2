// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../interfaces/core/IPrivateVaultAutomator.sol";

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract PrivateVaultAutomator is AccessControl, Pausable, IPrivateVaultAutomator {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner, address[] memory _operators) {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
    for (uint256 i = 0; i < _operators.length; i++) {
      _grantRole(OPERATOR_ROLE_HASH, _operators[i]);
    }
  }

  function executeMulticall(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    bytes32 hash,
    bytes memory signature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateOrder(hash, signature, vault.vaultOwner());
    vault.multicall(targets, callValues, data, callTypes);
  }

  /// @dev Validate the order
  /// @param hash Hash of the data to be signed
  /// @param signature Signature of the order
  /// @param actor Actor of the order
  function _validateOrder(bytes32 hash, bytes memory signature, address actor) internal view {
    require(SignatureChecker.isValidSignatureNow(actor, hash, signature), InvalidSignature());
    require(!_cancelledOrder[keccak256(signature)], OrderCancelled());
  }

  /// @notice Cancel an order
  /// @param hash Hash of the data to be signed
  /// @param signature Signature of the order
  function cancelOrder(bytes32 hash, bytes memory signature) external {
    _validateOrder(hash, signature, msg.sender);
    _cancelledOrder[keccak256(signature)] = true;
    emit CancelOrder(msg.sender, hash, signature);
  }

  /// @notice Check if an order is cancelled
  /// @param signature Signature of the order
  /// @return true if the order is cancelled
  function isOrderCancelled(bytes calldata signature) external view returns (bool) {
    return _cancelledOrder[keccak256(signature)];
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

  /// @notice Pause the contract
  function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpause the contract
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  receive() external payable { }

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
