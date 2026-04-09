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

```solidity
struct SwapParams {
  address tokenIn;
  uint256 amountIn;
  address tokenOut;
  uint256 amountOutMin;
  bytes swapData;
}
```

### SwapAndDepositParams

```solidity
struct SwapAndDepositParams {
  contract ISharedVault vault;
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

Pull input tokens, execute swaps to vault tokens, deposit proportionally, return leftovers.

_Swap calldata is built off-chain by the Krystal API swap aggregator.
     The gateway briefly holds tokens during the tx; nothing persists across calls._

### withdrawAndSwap

```solidity
function withdrawAndSwap(struct SharedVaultGateway.WithdrawAndSwapParams params) external returns (uint256[4] vaultAmounts)
```

Burn shares, receive vault tokens, execute swaps to desired output, return leftovers.

### _pullInputTokens

```solidity
function _pullInputTokens(struct SharedVaultGateway.SwapParams[] swaps) internal
```

_Pull all non-zero input tokens from _msgSender(). Native ETH arrives via msg.value._

### _executeSwaps

```solidity
function _executeSwaps(struct SharedVaultGateway.SwapParams[] swaps) internal
```

_Execute each swap via the configured swapRouter with opaque calldata.
     Pattern mirrors V3Utils._swap and V4Utils._swap — approve, call, verify delta, reset._

### _executeSingleSwap

```solidity
function _executeSingleSwap(struct SharedVaultGateway.SwapParams swap, uint256 index) internal
```

### _buildDepositAmounts

```solidity
function _buildDepositAmounts(address[4] vaultTokens, uint256[4] minDepositAmounts) internal view returns (uint256[4] amounts)
```

_Build deposit amounts array. For each vault token, use the gateway's current balance
     (post-swaps) but cap at no less than minDepositAmounts (which acts as the user hint
     for the proportional deposit computation inside SharedVault)._

### _approveVaultTokens

```solidity
function _approveVaultTokens(address[4] vaultTokens, uint256[4] amounts, address vault) internal
```

### _sweepAll

```solidity
function _sweepAll(address[] sweepTokens, address[4] vaultTokens, address recipient) internal
```

_Return all remaining balances of sweep tokens + vault tokens to the recipient.
     Also refunds any leftover native ETH._

### _sweepToken

```solidity
function _sweepToken(address token, address to) internal
```

### _sweepNative

```solidity
function _sweepNative(address to) internal
```

### receive

```solidity
receive() external payable
```

