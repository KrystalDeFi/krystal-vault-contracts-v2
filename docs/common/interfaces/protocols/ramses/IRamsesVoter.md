# Solidity API

## IRamsesVoter

The parts of Ramses' Voter the vault strategies read. Each Ramses deployment has one Voter, wired to its
        single CL position manager.

### nfpManager

```solidity
function nfpManager() external view returns (address)
```

The CL position manager whose positions this Voter's gauges reward.

### ram

```solidity
function ram() external view returns (address)
```

The token gauges pay emissions in.

### gaugeForPool

```solidity
function gaugeForPool(address pool) external view returns (address)
```

The gauge of `pool`, zero for a pool without one (fee-only).

