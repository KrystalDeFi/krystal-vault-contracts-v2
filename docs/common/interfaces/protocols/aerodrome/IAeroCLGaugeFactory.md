# Solidity API

## IAeroCLGaugeFactory

CL gauge factory of Aero (MetaDEX Slipstream). Legacy Aerodrome/Velodrome CLGaugeFactory contracts don't have
        `leafVoter()`, which is what tells the two apart.

### leafVoter

```solidity
function leafVoter() external view returns (address)
```

### emissionCap

```solidity
function emissionCap(address gauge) external view returns (uint128)
```

Emission cap of `gauge`; a gauge with a zero cap earns no emissions

