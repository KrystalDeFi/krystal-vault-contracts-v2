# Solidity API

## IAeroMessageOrchestrator

Aero's per-chain message orchestrator for redeems. On Base its adapter is the root-local adapter; on the
        other chains it is a cross-chain (Hyperlane) adapter.

### adapter

```solidity
function adapter() external view returns (address)
```

