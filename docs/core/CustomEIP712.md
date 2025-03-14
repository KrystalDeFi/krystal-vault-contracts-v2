# Solidity API

## CustomEIP712

### DOMAIN_SEPARATOR

```solidity
bytes32 DOMAIN_SEPARATOR
```

### constructor

```solidity
constructor(string name, string version) internal
```

### \_recover

```solidity
function _recover(bytes order, bytes signature) internal view returns (address)
```

_Recover signer of EIP712 signature_

#### Parameters

| Name      | Type  | Description            |
| --------- | ----- | ---------------------- |
| order     | bytes | ABI encoded order      |
| signature | bytes | Signature of the order |

#### Return Values

| Name | Type    | Description         |
| ---- | ------- | ------------------- |
| [0]  | address | Signer of the order |

### \_hashTypedDataV4

```solidity
function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32)
```

_Convert to typed data hash_

#### Parameters

| Name       | Type    | Description        |
| ---------- | ------- | ------------------ |
| structHash | bytes32 | Hash of the struct |

### toTypedDataHash

```solidity
function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest)
```

\_Returns the keccak256 digest of an EIP-712 typed data (EIP-191 version `0x01`).

The digest is calculated from a `domainSeparator` and a `structHash`, by prefixing them with `\x19\x01` and hashing the
result. It corresponds to the hash signed by the https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`] JSON-RPC
method as part of EIP-712.

See {ECDSA-recover}.\_
