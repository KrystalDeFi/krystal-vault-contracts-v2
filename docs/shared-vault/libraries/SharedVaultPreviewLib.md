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

