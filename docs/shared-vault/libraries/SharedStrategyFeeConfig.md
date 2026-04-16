# Solidity API

## SharedStrategyFeeConfig

`FeeConfig` for proportional LP exits (`LpFeeTaker`) when strategies run as the vault (delegatecall).
        V3-style `execute` paths set fee Q64 on `IV3Utils` calldata; V4 exit Q64 is built in `SharedV4Strategy`.

### performanceFeeConfig

```solidity
function performanceFeeConfig(uint16 vaultOwnerFeeBasisPoint) internal view returns (struct ICommon.FeeConfig fc)
```

`FeeConfig` for proportional LP exit (`LpFeeTaker`). Platform bps from config; withdraw exits never charge gas on principal.

