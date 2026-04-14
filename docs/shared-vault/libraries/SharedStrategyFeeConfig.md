# Solidity API

## SharedStrategyFeeConfig

Platform bps `0` => config; `type(uint16).max` => no platform fee. Gas X64 is caller-supplied for
        `execute` (no default); withdraw exits use no gas fee on principal.

### resolvePlatformBps

```solidity
function resolvePlatformBps(contract ISharedConfigManager cm, uint16 overrideBps) internal view returns (uint16)
```

_`overrideBps == 0` uses stored config platform fee._

### platformFeeX64

```solidity
function platformFeeX64(contract ISharedConfigManager cm, uint16 platformBpsOverride) internal view returns (uint64)
```

_Q64 for V3Utils `protocolFeeX64` / `Instructions.performanceFeeX64`.
     `type(uint16).max` forces zero protocol fee regardless of config (caller “waive platform fee”)._

### vaultOwnerFeeX64

```solidity
function vaultOwnerFeeX64(uint16 basisPoints) internal pure returns (uint64)
```

_Q64 for V4Utils `performanceFeeX64` (vault-owner performance share on LP exits)._

### performanceFeeConfig

```solidity
function performanceFeeConfig(uint16 vaultOwnerFeeBasisPoint) internal view returns (struct ICommon.FeeConfig fc)
```

`FeeConfig` for proportional LP exit (`LpFeeTaker`). Platform bps from config; withdraw exits never charge gas on principal.

