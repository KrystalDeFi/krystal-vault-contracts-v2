# Solidity API

## SharedVaultGateway

Simplifies deposits into and withdrawals from SharedVault by accepting arbitrary
        input tokens and executing pre-built swap calldata (from an off-chain aggregator API)
        to convert them into the vault's required proportional token mix.

Deposit flow:  user sends any tokens → gateway swaps to vault tokens → deposits to vault → returns shares + leftovers
Withdraw flow: user burns shares via gateway → receives vault tokens → gateway swaps to desired output → returns output + leftovers

### ZeroAddress

```solidity
error ZeroAddress()
```

### SwapFailed

```solidity
error SwapFailed(uint256 index)
```

### SlippageExceeded

```solidity
error SlippageExceeded(uint256 index)
```

### InsufficientShares

```solidity
error InsufficientShares()
```

### InvalidSwapRouter

```solidity
error InvalidSwapRouter()
```

### InsufficientPostSwapBalance

```solidity
error InsufficientPostSwapBalance(uint256 tokenIndex)
```

### EthTransferFailed

```solidity
error EthTransferFailed()
```

### InsufficientWithdrawBalance

```solidity
error InsufficientWithdrawBalance(uint256 swapIndex)
```

### IdenticalSwapTokens

```solidity
error IdenticalSwapTokens(uint256 index)
```

### TooManySwaps

```solidity
error TooManySwaps(uint256 count)
```

### ConflictingWethInput

```solidity
error ConflictingWethInput()
```

### SwapAndDeposit

```solidity
event SwapAndDeposit(address vault, address depositor, uint256 sharesReceived)
```

### WithdrawAndSwap

```solidity
event WithdrawAndSwap(address vault, address withdrawer, uint256 sharesBurned)
```

### SwapRouterUpdated

```solidity
event SwapRouterUpdated(address oldRouter, address newRouter)
```

### SwapParams

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |

```solidity
struct SwapParams {
  address tokenIn;
  uint256 amountIn;
  address tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### InputToken

A total token amount to pull from the caller upfront. The gateway holds the
        pulled balance for the rest of the call; swaps[] then optionally consume portions
        to produce vault tokens, and any remaining balance is deposited directly.

```solidity
struct InputToken {
  address token;
  uint256 amount;
}
```

### SwapAndDepositParams

```solidity
struct SwapAndDepositParams {
  contract ISharedVault vault;
  struct SharedVaultGateway.InputToken[] inputs;
  struct SharedVaultGateway.SwapParams[] swaps;
  uint256[4] minDepositAmounts;
  uint16 slippageBps;
  uint256 minShares;
  address[] sweepTokens;
}
```

### WithdrawAndSwapParams

```solidity
struct WithdrawAndSwapParams {
  contract ISharedVault vault;
  uint256 shares;
  uint256[4] minWithdrawAmounts;
  bool unwrapOnWithdraw;
  struct SharedVaultGateway.SwapParams[] swaps;
  address[] sweepTokens;
}
```

### BalanceSnapshot

```solidity
struct BalanceSnapshot {
  address[] tokens;
  uint256[] balances;
  uint256 count;
  uint256 nativeBalance;
}
```

### MAX_SWAPS

```solidity
uint256 MAX_SWAPS
```

Practical cap for one gateway swap pipeline. Bounds snapshot allocation and dedup loop cost.

### swapRouter

```solidity
address swapRouter
```

### weth

```solidity
address weth
```

### initialize

```solidity
function initialize(address _owner, address _swapRouter, address _weth) external
```

### setSwapRouter

```solidity
function setSwapRouter(address _swapRouter) external
```

### setPaused

```solidity
function setPaused(bool _paused) external
```

### swapAndDeposit

```solidity
function swapAndDeposit(struct SharedVaultGateway.SwapAndDepositParams params) external payable returns (uint256 shares)
```

Pull input tokens upfront, execute swaps from gateway balance to produce vault tokens,
        deposit proportionally, return leftovers.

_Swap calldata is built off-chain by the Krystal API swap aggregator.
     The gateway briefly holds tokens during the tx; nothing persists across calls.
     **Flow**: `inputs[]` declares the *total* amounts pulled from the caller (e.g. 10 USDC).
     `swaps[]` then specifies how portions of those balances are converted (e.g. swap 2 USDC → WETH).
     Whatever is not consumed by swaps remains in the gateway and is deposited directly to the vault
     (e.g. the remaining 8 USDC). Any post-deposit residue is swept back to the caller.
     **Native ETH**: if `msg.value > 0` it is wrapped to WETH before any swap runs, so the swap
     router only ever sees WETH. Swap entries that consume this WETH use `tokenIn == weth` with
     `amountIn == 0` (full balance) or a specific sub-amount. Any WETH that remains after swaps
     and deposit is unwrapped back to ETH and returned to the caller.
     **Swap skips**: `swapData.length == 0` means "skip this entry" only when `amountOutMin == 0`.
     A nonzero `amountOutMin` is treated as a hard per-swap slippage floor and reverts if no swap runs._

### withdrawAndSwap

```solidity
function withdrawAndSwap(struct SharedVaultGateway.WithdrawAndSwapParams params) external returns (uint256[4] vaultAmounts)
```

Burn shares, receive vault tokens, execute swaps to desired output, return leftovers.

_Swap entries with empty `swapData` are skipped only when `amountOutMin == 0`. A nonzero
     `amountOutMin` is enforced even when the resolved full-balance `amountIn` is zero._

### _requireSwapBatchWithinLimit

```solidity
function _requireSwapBatchWithinLimit(uint256 swapCount) internal pure
```

### _snapshotSwapAndDeposit

```solidity
function _snapshotSwapAndDeposit(struct SharedVaultGateway.SwapAndDepositParams params, address[4] vaultTokens) internal view returns (struct SharedVaultGateway.BalanceSnapshot snapshot)
```

### _snapshotWithdrawAndSwap

```solidity
function _snapshotWithdrawAndSwap(struct SharedVaultGateway.WithdrawAndSwapParams params, address[4] vaultTokens) internal view returns (struct SharedVaultGateway.BalanceSnapshot snapshot)
```

### _initBalanceSnapshot

```solidity
function _initBalanceSnapshot(uint256 maxTokens, uint256 nativeOffset) internal view returns (struct SharedVaultGateway.BalanceSnapshot snapshot)
```

### _addSnapshotSwapTokens

```solidity
function _addSnapshotSwapTokens(struct SharedVaultGateway.BalanceSnapshot snapshot, struct SharedVaultGateway.SwapParams[] swaps) internal view
```

### _addSnapshotVaultTokens

```solidity
function _addSnapshotVaultTokens(struct SharedVaultGateway.BalanceSnapshot snapshot, address[4] vaultTokens) internal view
```

### _addSnapshotSweepTokens

```solidity
function _addSnapshotSweepTokens(struct SharedVaultGateway.BalanceSnapshot snapshot, address[] sweepTokens) internal view
```

### _addSnapshotToken

```solidity
function _addSnapshotToken(struct SharedVaultGateway.BalanceSnapshot snapshot, address token) internal view
```

### _snapshotBalance

```solidity
function _snapshotBalance(struct SharedVaultGateway.BalanceSnapshot snapshot, address token) internal view returns (uint256)
```

### _balanceDelta

```solidity
function _balanceDelta(struct SharedVaultGateway.BalanceSnapshot snapshot, address token) internal view returns (uint256)
```

### _nativeDelta

```solidity
function _nativeDelta(struct SharedVaultGateway.BalanceSnapshot snapshot) internal view returns (uint256)
```

### _pullInputTokens

```solidity
function _pullInputTokens(struct SharedVaultGateway.InputToken[] inputs) internal returns (bool nativeWrapped)
```

_Wrap any native ETH to WETH first, then pull each declared input token in full from the caller.
     `token` must always be a real ERC20 address — `address(0)` is never valid here.

     There is exactly **one** WETH source per call:
     - Native ETH path  (`msg.value > 0`): the full `msg.value` is wrapped to WETH and is the sole
       WETH supply. A `token == weth` entry is only permitted with `amount == 0` (a no-op); a
       positive-amount WETH entry conflicts with the wrap and reverts with `ConflictingWethInput`
       rather than being silently dropped (which would under-deposit vs the caller's intent).
     - ERC20 WETH path (`msg.value == 0`): WETH is pulled from the caller's wallet via
       `transferFrom` for entries where `token == weth && amount > 0`.

     Other non-WETH ERC20 tokens are always pulled via `transferFrom` regardless of path._

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| nativeWrapped | bool | True when `msg.value > 0`; tells `_sweepAll` to unwrap any residual         WETH and return it as native ETH. |

### _executeSwaps

```solidity
function _executeSwaps(struct SharedVaultGateway.SwapParams[] swaps, struct SharedVaultGateway.BalanceSnapshot snapshot) internal
```

_Execute each swap via the configured swapRouter with opaque calldata.
     Pattern mirrors V3Utils._swap and V4Utils._swap — approve, call, verify delta, reset.
     Trust boundary for the opaque `swap.swapData` (W-17): these participant zap swaps are
     intentionally UNSIGNED, which is safe because the Gateway never touches pooled vault funds — it
     spends only balances pulled from the caller (or received from burning the caller's own vault
     shares) within this single transaction, and `_sweepAll` returns every leftover to the caller, so
     a misbehaving router can at worst waste the CALLER's own funds, bounded below by the caller's
     `minDepositAmounts` / `amountOutMin` floors. `swapRouter` is a single owner-configured address
     (not caller-chosen — see `setSwapRouter`); per swap the allowance is scoped to exactly `amountIn`
     and reset to 0 after the call; and the realized `tokenOut` delta must be >= `amountOutMin`. The
     per-call snapshot baseline (`_balanceDelta`) means a caller can never spend balances left by a
     prior caller. Operator swaps against POOLED vault funds take the strategy paths instead and DO
     require `SharedSwapDataSignature`._

### _executeSingleSwap

```solidity
function _executeSingleSwap(struct SharedVaultGateway.SwapParams swap, uint256 index, struct SharedVaultGateway.BalanceSnapshot snapshot) internal
```

### _buildDepositAmounts

```solidity
function _buildDepositAmounts(address[4] vaultTokens, uint256[4] vaultTotalBalances, uint256[4] minDepositAmounts, struct SharedVaultGateway.BalanceSnapshot snapshot) internal view returns (uint256[4] amounts)
```

_Use per-call gateway balance deltas as `amounts` for `vault.deposit`. `minDepositAmounts[i]` is a
     post-swap slippage floor: revert if the call delta is below the minimum for that vault token slot._

### _approveVaultTokens

```solidity
function _approveVaultTokens(address[4] vaultTokens, uint256[4] amounts, address vault) internal
```

### _revokeVaultTokenApprovals

```solidity
function _revokeVaultTokenApprovals(address[4] vaultTokens, address vault) internal
```

### _sweepAll

```solidity
function _sweepAll(address[] sweepTokens, address[4] vaultTokens, address recipient, bool unwrapWeth, struct SharedVaultGateway.BalanceSnapshot snapshot) internal
```

_Return all remaining balances of sweep tokens + vault tokens to the recipient.
     If `unwrapWeth` is true (native ETH was wrapped on the way in), any WETH still held by the
     gateway after token sweeps is unwrapped to ETH so the caller receives native ETH, not WETH.
     Also refunds any leftover native ETH._

### _sweepToken

```solidity
function _sweepToken(address token, address to, struct SharedVaultGateway.BalanceSnapshot snapshot) internal
```

### _sweepNative

```solidity
function _sweepNative(address to, struct SharedVaultGateway.BalanceSnapshot snapshot) internal
```

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view
```

Check if the caller has permission to withdraw

_Must be implemented by the child contract_

### receive

```solidity
receive() external payable
```

