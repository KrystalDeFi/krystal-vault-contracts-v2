# Solidity API

## ICreateX

### Values

```solidity
struct Values {
  uint256 constructorAmount;
  uint256 initCallAmount;
}
```

### ContractCreation

```solidity
event ContractCreation(address newContract, bytes32 salt)
```

### ContractCreation

```solidity
event ContractCreation(address newContract)
```

### Create3ProxyContractCreation

```solidity
event Create3ProxyContractCreation(address newContract, bytes32 salt)
```

### FailedContractCreation

```solidity
error FailedContractCreation(address emitter)
```

### FailedContractInitialisation

```solidity
error FailedContractInitialisation(address emitter, bytes revertData)
```

### InvalidSalt

```solidity
error InvalidSalt(address emitter)
```

### InvalidNonceValue

```solidity
error InvalidNonceValue(address emitter)
```

### FailedEtherTransfer

```solidity
error FailedEtherTransfer(address emitter, bytes revertData)
```

### deployCreate

```solidity
function deployCreate(bytes initCode) external payable returns (address newContract)
```

### deployCreateAndInit

```solidity
function deployCreateAndInit(bytes initCode, bytes data, struct ICreateX.Values values, address refundAddress) external payable returns (address newContract)
```

### deployCreateAndInit

```solidity
function deployCreateAndInit(bytes initCode, bytes data, struct ICreateX.Values values) external payable returns (address newContract)
```

### deployCreateClone

```solidity
function deployCreateClone(address implementation, bytes data) external payable returns (address proxy)
```

### computeCreateAddress

```solidity
function computeCreateAddress(address deployer, uint256 nonce) external view returns (address computedAddress)
```

### computeCreateAddress

```solidity
function computeCreateAddress(uint256 nonce) external view returns (address computedAddress)
```

### deployCreate2

```solidity
function deployCreate2(bytes32 salt, bytes initCode) external payable returns (address newContract)
```

### deployCreate2

```solidity
function deployCreate2(bytes initCode) external payable returns (address newContract)
```

### deployCreate2AndInit

```solidity
function deployCreate2AndInit(bytes32 salt, bytes initCode, bytes data, struct ICreateX.Values values, address refundAddress) external payable returns (address newContract)
```

### deployCreate2AndInit

```solidity
function deployCreate2AndInit(bytes32 salt, bytes initCode, bytes data, struct ICreateX.Values values) external payable returns (address newContract)
```

### deployCreate2AndInit

```solidity
function deployCreate2AndInit(bytes initCode, bytes data, struct ICreateX.Values values, address refundAddress) external payable returns (address newContract)
```

### deployCreate2AndInit

```solidity
function deployCreate2AndInit(bytes initCode, bytes data, struct ICreateX.Values values) external payable returns (address newContract)
```

### deployCreate2Clone

```solidity
function deployCreate2Clone(bytes32 salt, address implementation, bytes data) external payable returns (address proxy)
```

### deployCreate2Clone

```solidity
function deployCreate2Clone(address implementation, bytes data) external payable returns (address proxy)
```

### computeCreate2Address

```solidity
function computeCreate2Address(bytes32 salt, bytes32 initCodeHash, address deployer) external pure returns (address computedAddress)
```

### computeCreate2Address

```solidity
function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address computedAddress)
```

### deployCreate3

```solidity
function deployCreate3(bytes32 salt, bytes initCode) external payable returns (address newContract)
```

### deployCreate3

```solidity
function deployCreate3(bytes initCode) external payable returns (address newContract)
```

### deployCreate3AndInit

```solidity
function deployCreate3AndInit(bytes32 salt, bytes initCode, bytes data, struct ICreateX.Values values, address refundAddress) external payable returns (address newContract)
```

### deployCreate3AndInit

```solidity
function deployCreate3AndInit(bytes32 salt, bytes initCode, bytes data, struct ICreateX.Values values) external payable returns (address newContract)
```

### deployCreate3AndInit

```solidity
function deployCreate3AndInit(bytes initCode, bytes data, struct ICreateX.Values values, address refundAddress) external payable returns (address newContract)
```

### deployCreate3AndInit

```solidity
function deployCreate3AndInit(bytes initCode, bytes data, struct ICreateX.Values values) external payable returns (address newContract)
```

### computeCreate3Address

```solidity
function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address computedAddress)
```

### computeCreate3Address

```solidity
function computeCreate3Address(bytes32 salt) external view returns (address computedAddress)
```

