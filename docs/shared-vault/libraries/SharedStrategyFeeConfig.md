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

