# Solidity API

## SharedStrategyFeeConfig

Platform bps `0` => config; gas X64 always caller-supplied for `execute`; withdraw exits use no gas fee.

### resolvePlatformBps

```solidity
function resolvePlatformBps(contract ISharedConfigManager cm, uint16 overrideBps) internal view returns (uint16)
```

_`overrideBps == 0` uses stored config platform fee._

### platformFeeX64

```solidity
function platformFeeX64(contract ISharedConfigManager cm, uint16 platformBpsOverride) internal view returns (uint64)
```

_Q64 for V3Utils `protocolFeeX64` / `Instructions.performanceFeeX64`._

### performanceFeeConfig

```solidity
function performanceFeeConfig(uint16 vaultOwnerFeeBasisPoint) internal view returns (struct ICommon.FeeConfig fc)
```

`FeeConfig` for proportional LP exit (`LpFeeTaker`). Platform bps from config; withdraw exits never charge gas on principal.

