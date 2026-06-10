// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;
pragma abicoder v2;

library AgentAllowanceStructHash {
  function _hash(bytes memory abiEncodedAgentAllowance) internal pure returns (bytes32) {
    AgentAllowance memory obj = abi.decode(abiEncodedAgentAllowance, (AgentAllowance));
    return keccak256(abi.encode(AGENT_ALLOWANCE_TYPE_HASH, obj.vault, obj.signatureTime, obj.expirationTime));
  }

  bytes32 constant AGENT_ALLOWANCE_TYPE_HASH =
    keccak256("AgentAllowance(address vault,uint64 signatureTime,uint64 expirationTime)");

  /// @notice Broad-scope delegation: the signed allowance does NOT commit to specific
  ///         strategies, targets, or operation data. Signing grants any automator operator
  ///         permission to execute arbitrary whitelisted operations on the vault until
  ///         `expirationTime`. Vault owners should set short expiration windows and may
  ///         revoke early via `cancelOrder`.
  /// @dev    Trust model: the `OPERATOR_ROLE` holder is trusted to choose the `actions`; the owner's
  ///         signature authorizes a delegation WINDOW, not a specific operation. `executeWithUserOrder`
  ///         is NOT a one-time or more-scoped alternative — a user order is likewise reusable until
  ///         cancelled and does not bind the executed actions either. The only structural difference is
  ///         that this AgentAllowance commits to a concrete `vault` and an `expirationTime`, whereas a
  ///         user order binds neither; AgentAllowance is therefore the NARROWER of the two primitives.
  ///         Bound exposure with a short `expirationTime` and revoke via `cancelOrder`.
  struct AgentAllowance {
    address vault;
    uint64 signatureTime;
    uint64 expirationTime;
  }
}
