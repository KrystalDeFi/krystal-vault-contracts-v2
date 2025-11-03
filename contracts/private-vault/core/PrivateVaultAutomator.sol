// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../interfaces/core/IPrivateVaultAutomator.sol";
import "../../common/strategies/CustomEIP712.sol";

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PrivateVaultAutomator is CustomEIP712, AccessControl, Pausable, IPrivateVaultAutomator {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner, address[] memory _operators) CustomEIP712("V3AutomationOrder", "5.0") {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
    for (uint256 i = 0; i < _operators.length; i++) {
      _grantRole(OPERATOR_ROLE_HASH, _operators[i]);
    }
  }

  // @notice Execute a multicall with hash and signature verification
  /// @param vault Vault
  /// @param targets Targets to call
  /// @param callValues Call values
  /// @param data Data to pass to the calls
  /// @param callTypes Call types
  /// @param message Hash of the data to be signed
  /// @param signature Signature of the order
  function executeMulticall(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    string calldata message,
    bytes memory signature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    string memory addressStr = Strings.toHexString(uint256(uint160(address(vault))));
    bytes32 hash = keccak256(abi.encodePacked(message, addressStr));
    _validateOrder(hash, signature, vault.vaultOwner());
    vault.multicall(targets, callValues, data, callTypes);
  }

  /// @notice Execute a multicall with EIP-712 signature verification
  /// @param vault Vault
  /// @param targets Targets to call
  /// @param callValues Call values
  /// @param data Data to pass to the calls
  /// @param callTypes Call types
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeMulticall(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateOrder(abiEncodedUserOrder, orderSignature, vault.vaultOwner());
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
