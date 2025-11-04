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

  struct AgentAllowance {
    address vault;
    uint64 signatureTime;
    uint64 expirationTime;
  }
}
