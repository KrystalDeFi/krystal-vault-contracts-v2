# Solidity API

## ISharedVaultFactory

### DuplicateVaultName

```solidity
error DuplicateVaultName()
```

### VaultCreated

```solidity
event VaultCreated(address owner, address vault, string name)
```

### ConfigManagerSet

```solidity
event ConfigManagerSet(address configManager)
```

### VaultImplementationSet

```solidity
event VaultImplementationSet(address vaultImplementation)
```

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts, uint16 vaultOwnerFeeBasisPoint) external payable returns (address vault)
```

Create a shared vault with initial token deposits.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| name | string |  |
| tokens | address[4] |  |
| initialAmounts | uint256[4] |  |
| vaultOwnerFeeBasisPoint | uint16 | Basis points of LP performance/collection fees routed to the        vault owner on proportional exits (max 10_000). **Locked at vault creation** — there is        no setter on `ISharedVault`, so depositors can rely on the value seen at creation time. |

### createVault

```solidity
function createVault(string name, address[4] tokens, uint256[4] initialAmounts, uint16 vaultOwnerFeeBasisPoint, struct ISharedVault.Action[] actions) external payable returns (address vault)
```

Create a shared vault with initial deposits and run `execute(actions)` once (same semantics as `ISharedVault.execute`).

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| name | string |  |
| tokens | address[4] |  |
| initialAmounts | uint256[4] |  |
| vaultOwnerFeeBasisPoint | uint16 | Locked at creation — see overload above for full semantics. |
| actions | struct ISharedVault.Action[] |  |

### isVault

```solidity
function isVault(address vault) external view returns (bool)
```

