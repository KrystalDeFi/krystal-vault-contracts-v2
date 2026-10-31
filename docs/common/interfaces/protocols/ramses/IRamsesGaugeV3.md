# Solidity API

## IRamsesGaugeV3

The parts of a Ramses CL gauge (GaugeV3) the vault strategies read. Gauges are non-custodial: a position
        earns while its owner holds it, and only the position manager or the Voter may claim for it.

### earned

```solidity
function earned(address token, uint256 tokenId) external view returns (uint256)
```

`token` the position has earned and not yet claimed, net of rewards already recorded as forfeited.

### rewardValidator

```solidity
function rewardValidator() external view returns (address)
```

The anti-sybil validator the gauge consults on every claim, zero when none is set.

