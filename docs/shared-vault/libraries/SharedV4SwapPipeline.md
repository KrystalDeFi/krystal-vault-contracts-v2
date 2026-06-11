# Solidity API

## SharedV4SwapPipeline

### Swap

_Protocol-neutral swap descriptor. `ISharedV4Utils.SwapParams` and
     `ISharedPancakeV4Utils.SwapParams` are field-for-field identical; both `execute` and
     `executePancake` normalize their protocol-specific input into this single shape and run the
     exact same pipeline (`_run`). Keeping one implementation means the swap-pipeline trust
     boundary is written and audited in one place instead of two._

```solidity
struct Swap {
  address tokenIn;
  uint256 amountIn;
  address tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### Input

_Protocol-neutral input descriptor: an `InputTokenParams` entry with the currency already
     mapped to its vault token (native → WETH). Mirrors the `Swap` normalization pattern._

```solidity
struct Input {
  address token;
  uint256 amount;
}
```

### execute

```solidity
function execute(address swapRouter, address token0, address token1, uint256 amount0, uint256 amount1, struct ISharedV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

### executePancake

```solidity
function executePancake(address swapRouter, address token0, address token1, uint256 amount0, uint256 amount1, struct ISharedPancakeV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

### executeWithInputs

```solidity
function executeWithInputs(address swapRouter, address token0, address token1, struct ISharedV4Utils.InputTokenParams[] inputTokens, uint64 gasFeeX64, struct ISharedV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

_`execute` variant for the swap-and-mint / swap-and-increase entrypoints: validates and
     folds `inputTokens` into the pipeline before the hops run. Every positive-amount input
     must be a vault token; after the (cap-validated) gas-fee skim, pool-token inputs fold into
     the running `total0`/`total1` while any OTHER vault token — the "fund the LP from a third
     vault token" flow (V3/Aerodrome `swapSourceToken` parity) — seeds the intermediate ledger
     and must be consumed down to EXACTLY zero by signed swap hops. That ledger rule is the
     anti-siphon guard: historically a non-pool input could pay `amount * gasFeeX64 / Q64` to
     the fee recipient while the remainder dangled outside the LP accounting; now a dangling
     remainder reverts the whole operation, fee skim included. Zero-amount entries are
     tolerated (no-op for fee, totals, and ledger alike)._

### executePancakeWithInputs

```solidity
function executePancakeWithInputs(address swapRouter, address token0, address token1, struct ISharedPancakeV4Utils.InputTokenParams[] inputTokens, uint64 gasFeeX64, struct ISharedPancakeV4Utils.SwapParams[] swapParams) external returns (uint256 total0, uint256 total1)
```

_Pancake twin of `executeWithInputs` (infinity-core Currency normalization)._

