# Solidity API

## SharedStrategyFeeConfig

`FeeConfig` for generated LP-position fee settlement when strategies run as the vault (delegatecall).
        SharedVault settles all tracked positions before withdraws; strategy execute paths settle only the
        existing position they mutate. Utility-call gas fees are capped by shared config.

### performanceFeeConfig

```solidity
function performanceFeeConfig() internal view returns (struct ICommon.FeeConfig fc)
```

`FeeConfig` for proportional LP exit (settled by `SharedStrategyFees`).
Platform bps come from config; withdraw exits never charge gas on principal.

_If `platformBps + vault.vaultOwnerFeeBasisPoint() > 10_000`, the vault owner's share is silently clamped to
     `10_000 - platformBps` so the combined fee never exceeds 100%. This means a platform-fee increase after
     vault creation will reduce the vault owner's effective share without reverting. This is intentional
     (prevents a broken fee config from bricking exits), but vault owners should be aware that their configured
     share is a ceiling that the platform-fee level can push downward._

### validateGasFeeX64

```solidity
function validateGasFeeX64(uint64 gasFeeX64) internal view returns (uint64 validatedGasFeeX64, address gasFeeRecipient)
```

_Re-reads `configManager`, `maxGasFeeX64`, and `feeRecipient` on every call. These are
     tx-invariant (configManager is immutable on the vault, and no in-tx delegatecall path mutates
     the config), so a multi-skim entrypoint (e.g. V4 DECREASE_AND_SWAP / ADJUST_RANGE, which skim
     on both the collect and decrease sides) repeats these reads. Caching once at the entrypoint and
     threading the values down would save a few thousand gas in those paths only, but is deliberately
     NOT done: passing fee config through the settlement call chain adds stale-value risk to
     security-critical code for a sub-1% gas win. Keep the read local unless that trade-off changes._

