# Solidity API

## SharedVault

### MAGIC_VALUE

```solidity
bytes4 MAGIC_VALUE
```

### SHARES_PRECISION

```solidity
uint256 SHARES_PRECISION
```

### INITIAL_SHARES

```solidity
uint256 INITIAL_SHARES
```

_Fixed share count minted to the first depositor regardless of deposit amount.
     This decouples share units from any specific token's decimals and prevents
     the initial share price from being dictated by deposit size._

### configManager

```solidity
contract ISharedConfigManager configManager
```

### vaultOwner

```solidity
address vaultOwner
```

### vaultFactory

```solidity
address vaultFactory
```

### operator

```solidity
address operator
```

### weth

```solidity
address weth
```

### tokenCount

```solidity
uint16 tokenCount
```

### tokens

```solidity
address[4] tokens
```

### isVaultToken

```solidity
mapping(address => bool) isVaultToken
```

### admins

```solidity
mapping(address => bool) admins
```

### vaultOwnerFeeBasisPoint

```solidity
uint16 vaultOwnerFeeBasisPoint
```

Basis points of LP performance/collection fees routed to `vaultOwner` on proportional exits (max 10_000).

_Locked at initialization. There is intentionally no setter — the value the depositor saw at
     vault creation must remain the value applied to every subsequent withdrawal so the owner cannot
     retroactively raise their performance-fee cut on existing deposits._

### positions

```solidity
struct ISharedVault.Position[] positions
```

_Array of tracked LP positions_

### positionIndex

```solidity
mapping(bytes32 => uint256) positionIndex
```

_Quick lookup: keccak256(nfpm, tokenId) => index+1 (0 = not tracked)_

### onlyOwner

```solidity
modifier onlyOwner()
```

### onlyAuthorized

```solidity
modifier onlyAuthorized()
```

### onlyOperator

```solidity
modifier onlyOperator()
```

### whenVaultNotPaused

```solidity
modifier whenVaultNotPaused()
```

### initialize

```solidity
function initialize(string _name, address[4] _tokens, uint256[4] initialAmounts, address _owner, address _operator, address _configManager, address _weth, uint16 _vaultOwnerFeeBasisPoint) public
```

Initializes the shared vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _name | string |  |
| _tokens | address[4] |  |
| initialAmounts | uint256[4] |  |
| _owner | address |  |
| _operator | address | Initial vault operator. The operator role is fixed at initialization —                  there is no post-deploy setter. Pass address(0) for a vault with no operator. |
| _configManager | address |  |
| _weth | address |  |
| _vaultOwnerFeeBasisPoint | uint16 | Vault-owner performance fee basis points (≤ 10_000). Locked at                  init — there is no setter so the fee depositors saw at vault creation cannot be                  retroactively raised on existing positions. |

### deposit

```solidity
function deposit(uint256[4] amounts, uint16 slippageBps) external payable returns (uint256 shares)
```

Deposit tokens proportionally and receive shares.

_Share ratio is based on TOTAL balances (idle + LP positions valued by strategies).
     Send ETH via msg.value to auto-wrap to WETH; amounts[wethIndex] must equal msg.value.
     Only the needed WETH is wrapped; excess native ETH is sent back to the caller **after**
     minting shares so a malicious depositor cannot receive a refund callback between balance
     snapshots and share finalization (AMM / LP valuation manipulation)._

### _validateWethDeposit

```solidity
function _validateWethDeposit(uint256[4] amounts) internal view returns (uint256 wi)
```

_If caller sent ETH, returns validated WETH slot index; otherwise `type(uint256).max`._

### _firstDepositTransfers

```solidity
function _firstDepositTransfers(uint256[4] amounts) internal view returns (uint256[4] transferAmounts, uint256 sharesOut)
```

_First deposit — always mints `INITIAL_SHARES`; full `amounts` are transferred._

### _subsequentDepositTransfers

```solidity
function _subsequentDepositTransfers(uint256[4] amounts, uint256 currentTotalSupply, uint256[4] totalBalances) internal view returns (uint256[4] transferAmounts)
```

_Subsequent deposit — compute how many tokens to pull based on minimum ratio across tokens.
     Shares are NOT computed here; they are derived from the post-LP-deposit balance delta so
     that slippage-induced partial LP consumption is reflected in the final share count.

     **Dust-proof rounding**: proportional slices are rounded UP (ceiling) and then floored to
     `10 ** max(0, token.decimals() - configManager.minTokenPrecision())`. Without this:
       (a) when a vault holds dust (e.g., 50 wei USDT + 100e18 tokenA), a depositor providing
           `amounts = [1 USDT-worth of tokenA, 0]` would compute `transferAmounts[dust] = 0`
           (floor of 0.5 wei) and receive shares for free, diluting existing holders; and
       (b) when a token slot resolves to 1–few wei, SharedVaultGateway's swap aggregator
           cannot produce that exact micro-amount to satisfy the deposit.
     Rounding up + min-enforcement forces depositor overpayment on sub-threshold slices, so
     existing holders are never diluted and the gateway always sees a swappable amount._

### _minTokenAmt

```solidity
function _minTokenAmt(address token, uint8 prec) internal view returns (uint256)
```

_Returns 10 ** max(0, decimals - precision). Tokens with fewer decimals than the
     precision level get a floor of 1 (the smallest representable unit)._

### _computeSharesFromDelta

```solidity
function _computeSharesFromDelta(uint256 currentTotalSupply, uint256[4] balancesBefore, uint256[4] balancesAfter) internal view returns (uint256 shares)
```

_Compute shares earned by a depositor from the delta between pre- and post-LP-deposit balances.
     Uses the minimum ratio across all tokens (binding constraint) so that a token that saw less
     LP consumption due to slippage is not over-credited. Reverts if no balance increased.
     Tokens whose total balance did not strictly increase are skipped (avoids underflow if LP marks move down)._

### _wrapWethDeposit

```solidity
function _wrapWethDeposit(uint256 wi, uint256[4] transferAmounts) internal returns (uint256 excessEth)
```

_Wrap only `transferAmounts[wi]` from `msg.value` into WETH; return excess native ETH (not sent here)._

### _pullDepositTokensExcludingWethSlot

```solidity
function _pullDepositTokensExcludingWethSlot(uint256 wi, uint256[4] transferAmounts) internal
```

### _depositProportionalToAllPositions

```solidity
function _depositProportionalToAllPositions(uint256 currentTotalSupply, uint256[4] totalBalances, uint256[4] transferAmounts, uint16 slippageBps) internal
```

_Push proportional slices into tracked LP positions; no-op on first deposit or empty positions.

     **Principal-only scaling**: the per-position top-up ratio is derived from each position's
     *principal* (liquidity at the current price), NOT from `getPositionAmounts` which bundles
     uncollected fees. `increaseLiquidity` can only consume tokens at the range ratio dictated
     by the current tick, so mixing fee balances (whose ratio is set by historical swap flow, not
     the range) into the desired amounts would either leak into idle silently (slippageBps == 0)
     or revert via `amount*Min` (slippageBps > 0). Uncollected fees are therefore effectively
     treated as idle: they still count toward `_getTotalBalances` for share pricing, but they do
     not participate in the LP top-up. The depositor's proportional share of those fees remains
     in the vault as a slightly higher idle reserve (or gets collected and proportionally returned
     on the next `exitProportional`)._

### withdraw

```solidity
function withdraw(uint256 shares, uint256[4] minAmounts, bool unwrap) external returns (uint256[4] amounts)
```

Burn shares and withdraw proportional tokens.

_For each tracked LP position the vault delegatecalls the strategy to exit
     a proportional share of liquidity. Tokens returned to the vault are then
     included in the idle balance withdrawn to the caller.

     **Slippage protection model**: individual LP exits are called with
     minAmount0=0, minAmount1=0 by design. Per-position slippage guards are
     intentionally omitted so that a single position's tight bound cannot DoS
     the entire withdrawal. Instead, `minAmounts` provides aggregate per-token
     protection: if a sandwich attack reduces any LP exit return, the total
     `amounts[i]` decreases and the outer check reverts the whole tx. Callers
     should derive `minAmounts` from `previewWithdraw()` minus acceptable slippage._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 |  |
| minAmounts | uint256[4] |  |
| unwrap | bool | If true, any WETH output is unwrapped to native ETH before sending. |

### execute

```solidity
function execute(struct ISharedVault.Action[] actions) external
```

Execute one or more actions atomically. See ISharedCommon.CallType for full semantics.

  DELEGATECALL         — delegatecall target via ISharedStrategy.execute(data).
                         Result is PositionChange[]: LP positions are tracked.
                         New position entries (isAdd) require token0/token1 to be vault tokens.
                         Token-only operations (harvest, swap-reward) return an empty array.
  CALL                 — direct call to a swap aggregator.
                         action.data = abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapCalldata).
                         tokenIn/tokenOut must be vault tokens; output delta checked against minAmountOut.
  CALL_WITH_POSITIONS  — direct call to a target that returns PositionChange[].
                         action.data is forwarded as raw calldata; result is decoded as PositionChange[].
                         The target is stored as pos.strategy and will be delegatecalled via
                         exitProportional at withdrawal time — it must implement ISharedStrategy.
                         No token pre-approval or balance check is performed on this path:
                         the external contract manages its own token transfers (unlike CALL,
                         where the vault is the initiator and owns the approval flow).

### _applyPositionChanges

```solidity
function _applyPositionChanges(address strategy, bytes result) internal
```

_Decode a PositionChange[] from raw return bytes and update LP position tracking.
     DELEGATECALL path: same token0/token1 vault-token check as
     `_applyPositionChangesChecked` when recording a new position._

### _applyPositionChangesChecked

```solidity
function _applyPositionChangesChecked(address strategy, bytes result) internal
```

_Same as _applyPositionChanges but used for the CALL_WITH_POSITIONS path.
     Before tracking a new position, verifies that `strategy` implements ISharedStrategy
     by probing `getPositionAmounts`. Positions stored here are later exited via
     delegatecall to `exitProportional`; a target that lacks that selector would brick
     all future withdrawals for every vault depositor._

### getTokens

```solidity
function getTokens() external view returns (address[4])
```

### getIdleBalances

```solidity
function getIdleBalances() external view returns (uint256[4])
```

### getTotalBalances

```solidity
function getTotalBalances() external view returns (uint256[4])
```

### getPositionCount

```solidity
function getPositionCount() external view returns (uint256)
```

### getPosition

```solidity
function getPosition(uint256 index) external view returns (address strategy, address nfpm, uint256 tokenId, address token0, address token1)
```

### previewDeposit

```solidity
function previewDeposit(uint256[4] amounts) external view returns (uint256 shares)
```

### previewWithdraw

```solidity
function previewWithdraw(uint256 _shares) external view returns (uint256[4] amounts)
```

Preview token amounts returned for burning `_shares`.

_Computes proportional share of total balances (idle + LP position principal + uncollected fees).
     **Does NOT deduct LP exit fees** (platform fee and vault-owner performance fee) that are
     charged during the actual `withdraw()`. Actual received amounts will be slightly lower.
     Callers should apply an additional slippage margin beyond LP exit fees when deriving `minAmounts`._

### getMinDepositAmounts

```solidity
function getMinDepositAmounts() external view returns (uint256[4] minAmounts)
```

Per-token minimum amounts required for a subsequent deposit.

_Returns zeros on first deposit (totalSupply == 0) because no proportional floor applies.
     For subsequent deposits each non-zero-balance slot returns
     `10 ** max(0, token.decimals() - configManager.minTokenPrecision())`.
     Slots whose total balance is zero must be deposited at exactly zero; their entry is 0._

### sweepTokens

```solidity
function sweepTokens(address[] _tokens, uint256[] amounts, address to) external
```

### sweepNativeToken

```solidity
function sweepNativeToken(uint256 amount, address to) external
```

### sweepERC721

```solidity
function sweepERC721(address token, uint256 tokenId, address to) external
```

### sweepERC1155

```solidity
function sweepERC1155(address token, uint256 tokenId, uint256 amount, address to) external
```

### grantAdminRole

```solidity
function grantAdminRole(address _address) external
```

### revokeAdminRole

```solidity
function revokeAdminRole(address _address) external
```

### setPaused

```solidity
function setPaused(bool _paused) external
```

### transferOwnership

```solidity
function transferOwnership(address newOwner) external
```

### dropPosition

```solidity
function dropPosition(address nfpm, uint256 tokenId) external
```

Forcibly remove a position from vault tracking without exiting liquidity.

_See `ISharedVault.dropPosition` regarding asymmetric custody when `operator` is set._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT position manager that issued the position |
| tokenId | uint256 | The position token ID to drop |

### recoverPosition

```solidity
function recoverPosition(address nfpm, uint256 tokenId, address strategy, address token0, address token1) external
```

Recover a previously dropped position back into vault tracking.
        Pulls the NFT from the operator (caller must have approved this vault as spender),
        re-adds the position to tracking, and re-enables LP valuation and proportional exits.
        The strategy must be whitelisted in ConfigManager (it is delegatecalled on deposits/withdrawals).

_See `ISharedVault.recoverPosition` re `token0` / `token1` and vault token validation._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| nfpm | address | NFT position manager that issued the position |
| tokenId | uint256 | The position token ID to recover |
| strategy | address | Whitelisted strategy to use for this position (must implement ISharedStrategy) |
| token0 | address | Pool token0 (must be a configured vault token) |
| token1 | address | Pool token1 (must be a configured vault token) |

### isValidSignature

```solidity
function isValidSignature(bytes32 hash, bytes signature) public view returns (bytes4 magicValue)
```

_Should return whether the signature provided is valid for the provided data_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| hash | bytes32 | Hash of the data to be signed |
| signature | bytes | Signature byte array associated with _data |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

### decimals

```solidity
function decimals() public pure returns (uint8)
```

_Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).

Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.

NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}._

### _addPosition

```solidity
function _addPosition(address strategy, address nfpm, uint256 tokenId, address token0, address token1) internal
```

### _removePosition

```solidity
function _removePosition(address nfpm, uint256 tokenId) internal
```

### _wethIndex

```solidity
function _wethIndex() internal view returns (uint256)
```

_Returns the index of the WETH token in the tokens array, or type(uint256).max if not found._

### _getIdleBalances

```solidity
function _getIdleBalances() internal view returns (uint256[4] balances)
```

### _getTotalBalances

```solidity
function _getTotalBalances() internal view returns (uint256[4] balances)
```

Total balances including idle tokens + LP position amounts valued by strategies

### receive

```solidity
receive() external payable
```

