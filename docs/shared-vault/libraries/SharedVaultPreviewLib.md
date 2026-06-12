# Solidity API

## SharedVaultPreviewLib

### previewWithdraw

```solidity
function previewWithdraw(uint256 shares, uint256 currentTotalSupply, uint256[4] idleBalances, struct ISharedVault.Position[] positions, address[4] tokens, contract ISharedConfigManager configManager, uint16 vaultOwnerFeeBasisPoint) external view returns (uint256[4] amounts)
```

### previewDeposit

```solidity
function previewDeposit(uint256[4] amounts, uint256 currentTotalSupply, uint256[4] totalBalances, address[4] tokens, contract ISharedConfigManager configManager, uint256 initialShares) external view returns (uint256 shares)
```

### computeTotalBalances

```solidity
function computeTotalBalances(uint256[4] idleBalances, struct ISharedVault.Position[] positions, address[4] tokens, contract ISharedConfigManager configManager, uint16 vaultOwnerFeeBasisPoint) external view returns (uint256[4] balances)
```

### subsequentDepositTransfers

```solidity
function subsequentDepositTransfers(uint256[4] amounts, uint256 currentTotalSupply, uint256[4] totalBalances, address[4] tokens, contract ISharedConfigManager configManager) external view returns (uint256[4] transferAmounts)
```

Compute the proportional transfer amounts required for a subsequent deposit.
        Reverts with InvalidAmount if no binding token is found, or InvalidRatio if the
        caller-supplied amounts do not satisfy the vault's current ratio.

### minDepositAmounts

```solidity
function minDepositAmounts(uint256 currentTotalSupply, uint256[4] totalBalances, address[4] tokens, contract ISharedConfigManager configManager) external view returns (uint256[4] minAmounts)
```

Returns the minimum deposit amounts required by the current vault ratio.

### validatePositionAdd

```solidity
function validatePositionAdd(address strategy, address nfpm, uint256 tokenId, address token0, address token1, bool probeStrategy, bool vaultTokens) external view
```

Validation for tracking a new LP position, hosted here (moved out of SharedVault)
        purely to keep SharedVault under the EIP-170 deploy-size limit.

_Delegatecalled from SharedVault, so `address(this)` is the vault. Reverts (bubbling the
     same custom errors, in the same order, SharedVault used inline) when the position must
     not be tracked:
     - `probeStrategy`: probe `getPositionAmounts` to confirm the target can value the
       position before it is tracked (CALL_WITH_POSITIONS targets only).
     - Canonical token pair via `getPositionTokens`: a buggy target can report any vault-token
       pair but `_getTotalBalances()` would attribute LP value to the wrong assets,
       mispricing shares.
     - `vaultTokens`: the vault's own `isVaultToken[token0] && isVaultToken[token1]` verdict,
       passed in (this library cannot read vault storage) so the check keeps its original
       position before the ownership probe.
     - NFT ownership: an unowned position would misprice shares._

### verifyPositionExit

```solidity
function verifyPositionExit(address strategy, address nfpm, uint256 tokenId) external view
```

Before untracking a position, verify it is truly exited. If the vault still holds the
        NFT, require the strategy reports zero amounts — a non-zero value means a live LP
        position would be untracked, understating TVL and enabling mispriced
        deposits/withdrawals.

_Delegatecalled from SharedVault (`address(this)` is the vault); hosted here to keep
     SharedVault under the EIP-170 deploy-size limit._

### netAfterPerformanceFees

```solidity
function netAfterPerformanceFees(uint256 owed, uint16 platformBps, uint16 ownerBps) internal pure returns (uint256)
```

_Net LP-fee amount retained by shareholders after platform + owner performance fees.
     Mirrors `SharedStrategyFees.applyFees` EXACTLY so the per-position FEE term matches the on-chain
     collect to the wei: each fee is computed from the ORIGINAL `owed` amount with floor division
     (NOT from a running remainder) and applied SEQUENTIALLY (platform first, then owner), each
     clamped to the remaining balance. Withdraw exits never charge the gas fee, so it is omitted. A
     single combined-bps division (`owed * (10000 - platform - owner) / 10000`) rounds differently
     and under-reports the net by up to 1 wei per token per position. NOTE (W-7): matching the fee
     math makes the fee TERM exact, but `previewWithdraw` as a whole remains a close UPPER-BOUND
     estimate, not wei-exact — see its NatSpec for the residual per-component rounding._

