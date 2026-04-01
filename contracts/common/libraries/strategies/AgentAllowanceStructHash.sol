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
  ///         revoke early via `cancelOrder`. For one-time scoped operations, prefer
  ///         `executeWithUserOrder` which consumes the signature after a single use.
  struct AgentAllowance {
    address vault;
    uint64 signatureTime;
    uint64 expirationTime;
  }
}
