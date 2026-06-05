# Solidity API

## SharedSwapDataSignature

### STORAGE_SLOT

```solidity
bytes32 STORAGE_SLOT
```

_Replay-protection storage namespace:
     keccak256("krystal.shared-vault.swap-data-signature.storage").
     This is intentionally the plain namespace hash; changing it requires a consumed-digest migration.
     Public library calls write this layout in the caller's storage; production paths execute in
     SharedVault storage, so consumed digests are scoped per vault. Future vault upgrades must
     continue reserving this unstructured slot._

### Layout

```solidity
struct Layout {
  mapping(bytes32 => bool) consumedDigests;
}
```

### Envelope

```solidity
struct Envelope {
  bytes swapData;
  address vault;
  uint256 deadline;
  address signer;
  bytes32 nonce;
  bytes signature;
}
```

### decode

```solidity
function decode(bytes signedSwapData) internal pure returns (struct SharedSwapDataSignature.Envelope envelope)
```

_Signed envelope: abi.encode(rawSwapData, vault, deadline, signer, nonce, signature)._

### layout

```solidity
function layout() internal pure returns (struct SharedSwapDataSignature.Layout l)
```

### hash

```solidity
function hash(address vault, address signer, address swapRouter, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes swapData, uint256 deadline, bytes32 nonce) internal view returns (bytes32)
```

_Intentionally non-EIP-712: backend signers sign this raw digest directly. The digest
     includes chain id, vault, and deadline to bind signatures without changing the envelope ABI._

### verify

```solidity
function verify(contract ISharedConfigManager configManager, address expectedVault, address swapRouter, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes signedSwapData) public returns (bytes swapData)
```

_Validates signer authorization and binds `swapRouter` into the signed digest. Router
     whitelisting is caller-owned and must be checked before calling this function. Replay
     state is caller-scoped; in production this means per-vault replay protection, while the
     signed vault field prevents cross-vault use of the same signature. Whitelisted signers are
     privileged slippage/router-policy authorities and must be key-managed accordingly._

