# Solidity API

## Vault

### ADMIN_ROLE_HASH

```solidity
bytes32 ADMIN_ROLE_HASH
```

### principalToken

```solidity
address principalToken
```

### currentAssets

```solidity
mapping(address => mapping(uint256 => struct ICommon.Asset)) currentAssets
```

### constructor

```solidity
constructor() public
```

### initialize

```solidity
function initialize(struct ICommon.VaultCreateParams params, address _owner, address _vaultAutomator) public
```

### deposit

```solidity
function deposit(uint256 amount) external returns (uint256 shares)
```

### allocate

```solidity
function allocate(struct ICommon.Asset[] inputAssets, contract IStrategy strategy, bytes data) external
```

### deallocate

```solidity
function deallocate(contract IStrategy strategy, uint256 allocationAmount) external
```

### getTotalValue

```solidity
function getTotalValue() external returns (uint256)
```

### getAssetAllocations

```solidity
function getAssetAllocations() external returns (struct ICommon.Asset[] assets, uint256[] values)
```

