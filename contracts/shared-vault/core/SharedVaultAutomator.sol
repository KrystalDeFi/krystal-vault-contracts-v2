// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "../interfaces/ISharedVault.sol";
import "../interfaces/ISharedVaultAutomator.sol";
import "../../private-vault/core/CustomEIP712.sol";
import "../../common/libraries/strategies/AgentAllowanceStructHash.sol";
import "../../common/libraries/strategies/LpUniV3StructHash.sol";
import "../../common/Withdrawable.sol";

contract SharedVaultAutomator is CustomEIP712, AccessControl, Pausable, Withdrawable, ISharedVaultAutomator {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  /// @dev Keyed on `_cancelKey(canceller, digest)` (not the bare digest) so cancellation is scoped to
  ///      the order's own signer; see `cancelOrder` for why this prevents third-party cancellation DoS.
  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner, address[] memory _operators) CustomEIP712("V3AutomationOrder", "5.0") {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
    for (uint256 i = 0; i < _operators.length; i++) {
      _grantRole(OPERATOR_ROLE_HASH, _operators[i]);
    }
  }

  /// @inheritdoc ISharedVaultAutomator
  function executeWithAgentAllowance(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external override onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateAgentAllowance(abiEncodedAgentAllowance, signature, address(vault));
    vault.execute(actions);
  }

  /// @inheritdoc ISharedVaultAutomator
  function executeWithUserOrder(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external override onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateOrder(abiEncodedUserOrder, orderSignature, vault.vaultOwner());
    vault.execute(actions);
  }

  /// @inheritdoc ISharedVaultAutomator
  function cancelOrder(bytes32 hash, bytes memory signature) external override {
    // SignatureChecker: for EOA checks ECDSA recovery; for multisig calls EIP-1271.isValidSignature
    require(SignatureChecker.isValidSignatureNow(_msgSender(), hash, signature), InvalidSignature());
    // Key on (canceller, EIP-712 digest) — NOT the digest alone.
    //  - On the digest (not raw signature bytes): EIP-1271 multisig wallets can produce different
    //    valid signature bytes for the same digest on every call, so keying on signature bytes would
    //    let the owner bypass cancellation by re-signing. Digest-keying makes cancellation order-based.
    //  - Scoped to `_msgSender()` (the canceller): the order validators only consult the entry under
    //    the order's own signer (`_cancelKey(actor, digest)`). A third party who learns a digest and
    //    self-signs it therefore cancels only their own (never-consulted) entry and cannot grief the
    //    owner's order. Without this scoping any caller could brick any known digest.
    _cancelledOrder[_cancelKey(_msgSender(), hash)] = true;
    emit CancelOrder(_msgSender(), hash, signature);
  }

  /// @inheritdoc ISharedVaultAutomator
  function isOrderCancelled(address actor, bytes32 hash) external view override returns (bool) {
    return _cancelledOrder[_cancelKey(actor, hash)];
  }

  /// @inheritdoc ISharedVaultAutomator
  function grantOperator(address operator) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @inheritdoc ISharedVaultAutomator
  function revokeOperator(address operator) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @notice Pause the automator
  function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpause the automator
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  /// @inheritdoc Withdrawable
  function _checkWithdrawPermission() internal view override {
    _checkRole(DEFAULT_ADMIN_ROLE);
  }

  receive() external payable {}

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  // ─── Internal helpers ────────────────────────────────────────────────────

  function _validateAgentAllowance(
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature,
    address vault
  ) internal view {
    AgentAllowanceStructHash.AgentAllowance memory allowance = abi.decode(
      abiEncodedAgentAllowance,
      (AgentAllowanceStructHash.AgentAllowance)
    );
    require(allowance.vault == vault, InvalidSignature());
    require(allowance.expirationTime >= block.timestamp, InvalidSignature());
    // Use SignatureChecker to support both EOA (ECDSA) and smart contract wallets (EIP-1271 multisig)
    bytes32 digest = _hashTypedDataV4(AgentAllowanceStructHash._hash(abiEncodedAgentAllowance));
    address owner = ISharedVault(vault).vaultOwner();
    require(SignatureChecker.isValidSignatureNow(owner, digest, signature), InvalidSignature());
    // Consult the cancellation entry scoped to the allowance signer (the vault owner), so only the
    // owner's own cancellation revokes the allowance.
    require(!_cancelledOrder[_cancelKey(owner, digest)], OrderCancelled());
  }

  /// @dev Validate the order
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  /// @param actor Actor of the order
  function _validateOrder(bytes memory abiEncodedUserOrder, bytes memory orderSignature, address actor) internal view {
    bytes32 digest = _hashTypedDataV4(StructHash._hash(abiEncodedUserOrder));
    require(SignatureChecker.isValidSignatureNow(actor, digest, orderSignature), InvalidSignature());
    // Consult the cancellation entry scoped to the order signer (`actor`), so only that signer's own
    // cancellation revokes the order — a third party self-signing the digest cannot grief it.
    require(!_cancelledOrder[_cancelKey(actor, digest)], OrderCancelled());
  }

  /// @dev Cancellation key, scoped to the order signer / canceller so cancellation is per-actor rather
  ///      than global. `abi.encode` (not `encodePacked`) keeps the address and digest fields unambiguous.
  function _cancelKey(address actor, bytes32 digest) private pure returns (bytes32) {
    return keccak256(abi.encode(actor, digest));
  }
}
