# Solidity API

## SharedStrategyBeacon

Stores the current implementation address for a SharedVault strategy type.
        Owned by the protocol multisig; upgrading calls setImplementation().
        All SharedStrategyProxy instances pointing to this beacon immediately use the
        new implementation without any per-vault or per-position migration.

### implementation

```solidity
address implementation
```

### ImplementationUpgraded

```solidity
event ImplementationUpgraded(address oldImpl, address newImpl)
```

### constructor

```solidity
constructor(address _implementation, address _owner) public
```

### setImplementation

```solidity
function setImplementation(address newImplementation) external
```

Upgrade the strategy implementation. Only the owner (protocol deployer) can call this.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newImplementation | address | New strategy logic contract address |

