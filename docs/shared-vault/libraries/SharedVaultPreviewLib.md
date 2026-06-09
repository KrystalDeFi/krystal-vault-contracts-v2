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

