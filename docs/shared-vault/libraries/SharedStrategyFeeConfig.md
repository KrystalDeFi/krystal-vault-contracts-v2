# Solidity API

## SharedStrategyFeeConfig

`FeeConfig` for proportional LP exits (`LpFeeTaker`) when strategies run as the vault (delegatecall).
        V3-style `execute` paths set fee Q64 on `IV3Utils` calldata; V4 exit Q64 is built in `SharedV4Strategy`.

### performanceFeeConfig

```solidity
function performanceFeeConfig(uint16 vaultOwnerFeeBasisPoint) internal view returns (struct ICommon.FeeConfig fc)
```

`FeeConfig` for proportional LP exit (`LpFeeTaker`). Platform bps from config; withdraw exits never charge gas on principal.

_If `platformBps + vaultOwnerFeeBasisPoint > 10_000`, the vault owner's share is silently clamped to
     `10_000 - platformBps` so the combined fee never exceeds 100%. This means a platform-fee increase after
     vault creation will reduce the vault owner's effective share without reverting. This is intentional
     (prevents a broken fee config from bricking exits), but vault owners should be aware that their configured
     share is a ceiling that the platform-fee level can push downward._

