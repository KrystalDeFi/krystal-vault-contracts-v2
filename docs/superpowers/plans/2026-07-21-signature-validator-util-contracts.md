# SignatureValidator (util-contracts) + PrivateVaultAutomator Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a reusable `SignatureValidator` Solidity library (in the `util-contracts` repo) that accepts a signature via ERC-1271 **OR** ECDSA recovery (both attempted, unconditionally), plus full ERC-6492 support, and wire it into `PrivateVaultAutomator.sol` so a PrivateVault owned by a Trust Wallet Biz (EIP-7702) or Coinbase Smart Wallet is operable **without redeploying the vault**.

**Architecture:** The current automator uses OZ `SignatureChecker.isValidSignatureNow`, which branches on `signer.code.length` — no-code → ECDSA, has-code → ERC-1271, mutually exclusive. An EIP-7702 account has *both* code and a key, so it can sign as a raw EOA yet `SignatureChecker` routes only to ERC-1271 and rejects the raw signature. `SignatureValidator.isValidSignatureNow` runs **both** legs and ORs them, so it accepts a raw-EOA-signed 7702 signature *and* an ERC-1271 (Coinbase / passkey / wrapped-Biz) signature. Only `PrivateVaultAutomator.sol` changes; the vault stays deployed because the automator is a whitelisted caller and performs the owner-signature check itself.

**Tech Stack:** Solidity 0.8.28 (library pragma `^0.8.20`), Foundry (forge 1.7.1), OpenZeppelin Contracts 5.2.0 (`ECDSA`, `IERC1271`), yarn (github dependency), via-IR, evm cancun.

## Global Constraints

- Library pragma: `pragma solidity ^0.8.20;` — compiles under the parent's pinned `solc 0.8.28`. (verbatim floor: `^0.8.20`)
- Library license: `// SPDX-License-Identifier: MIT`. Parent contract files keep `BUSL-1.1`.
- ERC-1271 magic value: `0x1626ba7e` (verbatim).
- ERC-6492 detection suffix (last 32 bytes): `0x6492649264926492649264926492649264926492649264926492649264926492` (verbatim).
- ERC-6492 wrapped-signature layout: `abi.encode(address factory, bytes factoryCalldata, bytes innerSignature)` concatenated with the 32-byte detection suffix.
- OZ ECDSA API: `(address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, sig);` — accept only when `err == ECDSA.RecoverError.NoError && recovered == signer`. Never use `ECDSA.recover` (it reverts).
- util-contracts package name: `@krystal/util-contracts`; consumed by the parent as `github:KrystalDeFi/util-contracts`. Import path: `@krystal/util-contracts/contracts/SignatureValidator.sol`.
- Parent remapping to add: `@krystal/util-contracts/=node_modules/@krystal/util-contracts/` (maps to package **root**, mirroring the repo's `@openzeppelin/=node_modules/@openzeppelin/`; the `contracts/` segment lives in the import path, NOT the remapping — otherwise it doubles to `contracts/contracts/`).
- Scope: change **only** `contracts/private-vault/core/PrivateVaultAutomator.sol` in the parent. Do NOT touch `PrivateVault.sol`, public-vault, or shared-vault sites.
- Foundry test runs in this repo require: `dangerouslyDisableSandbox` + `FOUNDRY_OFFLINE=true` + `--offline`, and the canonical `RPC_URL=https://mainnet.base.org` for cached fork reads. New non-fork tests avoid RPC entirely.

---

### Task 1: Scaffold `util-contracts` + `SignatureValidator` dual-path core

**Files:**
- Create: `../util-contracts/foundry.toml`
- Create: `../util-contracts/remappings.txt`
- Create: `../util-contracts/package.json`
- Create: `../util-contracts/.gitignore`
- Create: `../util-contracts/contracts/SignatureValidator.sol`
- Test: `../util-contracts/test/SignatureValidator.t.sol`
- Submodule: `../util-contracts/lib/forge-std`

**Interfaces:**
- Consumes: OZ `ECDSA`, OZ `IERC1271` (installed via npm into `../util-contracts/node_modules/@openzeppelin`).
- Produces:
  - `SignatureValidator.isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool)`
  - `SignatureValidator.isValidSignatureNowWithSideEffects(address signer, bytes32 hash, bytes memory signature) internal returns (bool)`
  - `SignatureValidator.ERC1271_MAGIC_VALUE` (`bytes4 = 0x1626ba7e`)
  - `SignatureValidator.ERC6492_DETECTION_SUFFIX` (`bytes32`)

- [ ] **Step 1: Scaffold the Foundry project**

Create `../util-contracts/foundry.toml`:

```toml
[profile.default]
src = 'contracts'
out = 'out'
libs = ['node_modules', 'lib']
test = 'test'
optimizer = true
optimizer_runs = 150
via_ir = true
solc_version = '0.8.28'
evm_version = 'cancun'
bytecode_hash = 'none'

[fmt]
bracket_spacing = true
int_types = "long"
line_length = 120
tab_width = 2
quote_style = "double"
number_underscore = "thousands"
```

Create `../util-contracts/remappings.txt`:

```
forge-std/=lib/forge-std/src/
@openzeppelin/=node_modules/@openzeppelin/
```

Create `../util-contracts/package.json`:

```json
{
  "name": "@krystal/util-contracts",
  "version": "0.1.0",
  "description": "Krystal utility smart contracts",
  "license": "MIT",
  "repository": "git@github.com:KrystalDeFi/util-contracts.git",
  "files": ["contracts"],
  "dependencies": {
    "@openzeppelin/contracts": "^5.2.0"
  }
}
```

Create `../util-contracts/.gitignore`:

```
node_modules/
out/
cache/
cache_forge/
```

- [ ] **Step 2: Install dependencies**

```bash
cd ../util-contracts
forge install foundry-rs/forge-std --no-commit || git submodule add https://github.com/foundry-rs/forge-std lib/forge-std
npm install
```

Expected: `lib/forge-std` populated, `node_modules/@openzeppelin/contracts` present.

- [ ] **Step 3: Write the failing test**

Create `../util-contracts/test/SignatureValidator.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { SignatureValidator } from "../contracts/SignatureValidator.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @dev Smart wallet that accepts a raw ECDSA signature over `hash` from a fixed owner key.
contract MockERC1271Wallet {
  bytes4 constant MAGIC = 0x1626ba7e;
  address public immutable owner;
  constructor(address _owner) { owner = _owner; }
  function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    (address rec, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, sig);
    return (err == ECDSA.RecoverError.NoError && rec == owner) ? MAGIC : bytes4(0xffffffff);
  }
}

/// @dev A Biz-style 7702 delegate: only accepts a signature over an EIP-712-WRAPPED hash, and
///      requires recover(...) == address(this). Etched onto an EOA to simulate 7702.
contract MockWrapped7702Wallet {
  bytes4 constant MAGIC = 0x1626ba7e;
  function wrap(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Wrapped:", block.chainid, address(this), hash));
  }
  function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    (address rec, ECDSA.RecoverError err, ) = ECDSA.tryRecover(wrap(hash), sig);
    return (err == ECDSA.RecoverError.NoError && rec == address(this)) ? MAGIC : bytes4(0xffffffff);
  }
}

contract SignatureValidatorTest is Test {
  bytes32 constant HASH = keccak256("krystal-order-digest");

  function test_eoa_rawSig_valid() public {
    uint256 pk = 0xA11CE;
    address eoa = vm.addr(pk);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, HASH);
    bytes memory sig = abi.encodePacked(r, s, v);
    assertTrue(SignatureValidator.isValidSignatureNow(eoa, HASH, sig));
  }

  function test_eoa_wrongKey_invalid() public {
    address eoa = vm.addr(0xA11CE);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBEEF, HASH);
    assertFalse(SignatureValidator.isValidSignatureNow(eoa, HASH, abi.encodePacked(r, s, v)));
  }

  function test_contractWallet_erc1271_valid() public {
    uint256 pk = 0xC0FFEE;
    MockERC1271Wallet w = new MockERC1271Wallet(vm.addr(pk));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, HASH);
    assertTrue(SignatureValidator.isValidSignatureNow(address(w), HASH, abi.encodePacked(r, s, v)));
  }

  function test_contractWallet_wrongKey_invalid() public {
    MockERC1271Wallet w = new MockERC1271Wallet(vm.addr(0xC0FFEE));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, HASH);
    assertFalse(SignatureValidator.isValidSignatureNow(address(w), HASH, abi.encodePacked(r, s, v)));
  }

  // THE 7702 FIX: account has code AND a key; owner signs the RAW hash.
  function test_7702_rawEoaSig_valid_whenErc1271WouldReject() public {
    uint256 pk = 0x7702;
    address acct = vm.addr(pk);
    MockWrapped7702Wallet impl = new MockWrapped7702Wallet();
    vm.etch(acct, address(impl).code); // 7702: code + key at the same address

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, HASH); // raw sig over HASH
    bytes memory rawSig = abi.encodePacked(r, s, v);

    // ERC-1271 leg fails (wallet wants the wrapped hash) → OZ SignatureChecker rejects.
    assertFalse(SignatureChecker.isValidSignatureNow(acct, HASH, rawSig));
    // Our dual-path accepts via the ECDSA leg.
    assertTrue(SignatureValidator.isValidSignatureNow(acct, HASH, rawSig));
  }

  // Same 7702 account, but signing the WRAPPED hash → ERC-1271 leg accepts.
  function test_7702_wrappedSig_valid_viaErc1271() public {
    uint256 pk = 0x7702;
    address acct = vm.addr(pk);
    MockWrapped7702Wallet impl = new MockWrapped7702Wallet();
    vm.etch(acct, address(impl).code);

    bytes32 wrapped = MockWrapped7702Wallet(acct).wrap(HASH);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, wrapped);
    assertTrue(SignatureValidator.isValidSignatureNow(acct, HASH, abi.encodePacked(r, s, v)));
  }

  function test_zeroSigner_invalid() public {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, HASH);
    assertFalse(SignatureValidator.isValidSignatureNow(address(0), HASH, abi.encodePacked(r, s, v)));
  }

  function test_garbageSig_invalid() public {
    address eoa = vm.addr(0xA11CE);
    assertFalse(SignatureValidator.isValidSignatureNow(eoa, HASH, hex"deadbeef"));
  }
}
```

- [ ] **Step 4: Run test to verify it fails**

```bash
cd ../util-contracts && forge test --match-contract SignatureValidatorTest -vvv
```

Expected: FAIL — `SignatureValidator.sol` does not exist / does not compile.

- [ ] **Step 5: Write the library**

Create `../util-contracts/contracts/SignatureValidator.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title SignatureValidator
/// @notice Dual-path signature validation: a signature is accepted if EITHER an ERC-1271 check OR
///         an ECDSA recovery succeeds. Unlike OpenZeppelin/Solady `SignatureChecker`, which selects
///         exactly one path based on `signer.code.length` (no code -> ECDSA, code -> ERC-1271),
///         this library attempts BOTH. That is required for EIP-7702 accounts, which have contract
///         code AND a controlling EOA key: such an account may present a raw EOA signature (ECDSA
///         leg) or a signature its delegate validates via `isValidSignature` (ERC-1271 leg).
///         ERC-6492 wrapped signatures are supported for counterfactual (not-yet-deployed) accounts.
library SignatureValidator {
  /// @dev ERC-1271 magic value: `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
  bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

  /// @dev ERC-6492 detection suffix (the last 32 bytes of a wrapped signature).
  bytes32 internal constant ERC6492_DETECTION_SUFFIX =
    0x6492649264926492649264926492649264926492649264926492649264926492;

  /// @notice VIEW dual-path validation. Returns true if `signature` is valid for `signer` via
  ///         ERC-1271 (attempted only when `signer` has code) OR ECDSA recovery (always attempted).
  ///         If `signature` is ERC-6492-wrapped it is unwrapped first; the factory-deploy prepare
  ///         step is NOT performed here (this is a view), so a not-yet-deployed account returns false.
  function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature)
    internal
    view
    returns (bool)
  {
    if (signer == address(0)) return false;
    bytes memory sig = signature;
    if (_isERC6492(sig)) {
      (,, bytes memory inner) = _decodeERC6492(sig);
      sig = inner;
    }
    return _dualCheck(signer, hash, sig);
  }

  /// @notice NON-VIEW full ERC-6492. If `signature` is 6492-wrapped and `signer` has no code, calls
  ///         `factory` with `factoryCalldata` to deploy the account, then runs the dual-path check.
  ///         Never reverts on an invalid signature; returns false instead.
  function isValidSignatureNowWithSideEffects(address signer, bytes32 hash, bytes memory signature)
    internal
    returns (bool)
  {
    if (signer == address(0)) return false;
    bytes memory sig = signature;
    if (_isERC6492(sig)) {
      (address factory, bytes memory factoryCalldata, bytes memory inner) = _decodeERC6492(sig);
      if (signer.code.length == 0 && factory != address(0)) {
        // Best-effort deploy; if it fails the dual-path below simply returns false.
        (bool ok,) = factory.call(factoryCalldata);
        ok;
      }
      sig = inner;
    }
    return _dualCheck(signer, hash, sig);
  }

  // ---------------------------------------------------------------------------------------------
  // internal helpers
  // ---------------------------------------------------------------------------------------------

  function _dualCheck(address signer, bytes32 hash, bytes memory sig) private view returns (bool) {
    // Leg 1: ERC-1271 (only meaningful when the signer has code).
    if (signer.code.length != 0 && _isValidERC1271(signer, hash, sig)) return true;
    // Leg 2: ECDSA — attempted EVEN when the signer has code (the EIP-7702 case).
    (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, sig);
    return err == ECDSA.RecoverError.NoError && recovered == signer;
  }

  function _isValidERC1271(address signer, bytes32 hash, bytes memory sig) private view returns (bool) {
    (bool ok, bytes memory ret) =
      signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, sig)));
    return ok && ret.length >= 32 && abi.decode(ret, (bytes4)) == ERC1271_MAGIC_VALUE;
  }

  function _isERC6492(bytes memory sig) private pure returns (bool) {
    if (sig.length < 32) return false;
    bytes32 suffix;
    assembly {
      suffix := mload(add(add(sig, 0x20), sub(mload(sig), 32)))
    }
    return suffix == ERC6492_DETECTION_SUFFIX;
  }

  function _decodeERC6492(bytes memory sig)
    private
    pure
    returns (address factory, bytes memory factoryCalldata, bytes memory inner)
  {
    uint256 bodyLen = sig.length - 32;
    bytes memory body = new bytes(bodyLen);
    assembly {
      let src := add(sig, 0x20)
      let dst := add(body, 0x20)
      for { let i := 0 } lt(i, bodyLen) { i := add(i, 0x20) } { mstore(add(dst, i), mload(add(src, i))) }
    }
    (factory, factoryCalldata, inner) = abi.decode(body, (address, bytes, bytes));
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd ../util-contracts && forge test --match-contract SignatureValidatorTest -vvv
```

Expected: PASS — 8 tests. In particular `test_7702_rawEoaSig_valid_whenErc1271WouldReject` proves OZ returns false while `SignatureValidator` returns true.

- [ ] **Step 7: Commit**

```bash
cd ../util-contracts
git add foundry.toml remappings.txt package.json .gitignore .gitmodules contracts test lib
git commit -m "feat: SignatureValidator dual-path (ERC-1271 OR ECDSA) with 7702 support"
```

---

### Task 2: ERC-6492 support tests (view unwrap + non-view deploy)

**Files:**
- Modify: `../util-contracts/test/SignatureValidator.t.sol` (append 6492 mocks + tests)

**Interfaces:**
- Consumes: `SignatureValidator.isValidSignatureNow`, `SignatureValidator.isValidSignatureNowWithSideEffects`, `SignatureValidator.ERC6492_DETECTION_SUFFIX` (from Task 1).
- Produces: no new public interface — validates existing 6492 behavior.

- [ ] **Step 1: Write the failing tests**

Append to `../util-contracts/test/SignatureValidator.t.sol` (inside a new contract so mocks stay isolated):

```solidity
/// @dev CREATE2 factory that deploys a MockERC1271Wallet at a deterministic address.
contract Mock6492Factory {
  function deploy(bytes32 salt, address owner) external returns (address addr) {
    bytes memory code = abi.encodePacked(type(MockERC1271Wallet).creationCode, abi.encode(owner));
    assembly {
      addr := create2(0, add(code, 0x20), mload(code), salt)
    }
  }
  function predict(bytes32 salt, address owner) external view returns (address) {
    bytes32 h = keccak256(
      abi.encodePacked(
        bytes1(0xff), address(this), salt,
        keccak256(abi.encodePacked(type(MockERC1271Wallet).creationCode, abi.encode(owner)))
      )
    );
    return address(uint160(uint256(h)));
  }
}

contract SignatureValidator6492Test is Test {
  bytes32 constant HASH = keccak256("krystal-order-digest");
  bytes32 constant SALT = bytes32(uint256(1));

  Mock6492Factory factory;
  uint256 ownerPk = 0xC0FFEE;
  address counterfactual;
  bytes wrappedSig;

  function setUp() public {
    factory = new Mock6492Factory();
    counterfactual = factory.predict(SALT, vm.addr(ownerPk));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, HASH);
    bytes memory inner = abi.encodePacked(r, s, v);
    bytes memory factoryCalldata = abi.encodeCall(Mock6492Factory.deploy, (SALT, vm.addr(ownerPk)));
    wrappedSig = abi.encodePacked(
      abi.encode(address(factory), factoryCalldata, inner),
      SignatureValidator.ERC6492_DETECTION_SUFFIX
    );
  }

  function test_6492_view_beforeDeploy_invalid() public {
    assertEq(counterfactual.code.length, 0);
    assertFalse(SignatureValidator.isValidSignatureNow(counterfactual, HASH, wrappedSig));
  }

  function test_6492_sideEffects_deploysAndValidates() public {
    assertEq(counterfactual.code.length, 0);
    assertTrue(SignatureValidator.isValidSignatureNowWithSideEffects(counterfactual, HASH, wrappedSig));
    assertGt(counterfactual.code.length, 0); // factory deployed it
  }

  function test_6492_view_afterDeploy_valid() public {
    factory.deploy(SALT, vm.addr(ownerPk)); // account now exists
    assertTrue(SignatureValidator.isValidSignatureNow(counterfactual, HASH, wrappedSig));
  }
}
```

- [ ] **Step 2: Run tests to verify they fail then pass**

```bash
cd ../util-contracts && forge test --match-contract SignatureValidator6492Test -vvv
```

Expected: after Task 1's library is present, all 3 pass. (`test_6492_view_beforeDeploy_invalid` passes because the view path does not deploy; `test_6492_sideEffects_deploysAndValidates` passes because the non-view path calls the factory.)

- [ ] **Step 3: Run the full util-contracts suite**

```bash
cd ../util-contracts && forge test -vvv
```

Expected: PASS — 11 tests total (8 + 3).

- [ ] **Step 4: Commit**

```bash
cd ../util-contracts
git add test/SignatureValidator.t.sol
git commit -m "test: ERC-6492 view-unwrap + side-effects-deploy coverage"
```

---

### Task 3: util-contracts README + local commit (push deferred to Task 8)

**Files:**
- Modify: `../util-contracts/README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Write the README**

Replace `../util-contracts/README.md`:

```markdown
# util-contracts

Krystal utility smart contracts.

## SignatureValidator

Dual-path signature validation: a signature is valid if **either** an ERC-1271
check **or** an ECDSA recovery succeeds. Unlike OZ/Solady `SignatureChecker`
(which picks one path by `signer.code.length`), this attempts both — required
for EIP-7702 accounts that have code *and* a key. Supports ERC-6492 wrapped
signatures for counterfactual accounts.

```solidity
import { SignatureValidator } from "@krystal/util-contracts/contracts/SignatureValidator.sol";

// view (no deploy): used by on-chain validators
SignatureValidator.isValidSignatureNow(signer, hash, signature);

// non-view (deploys a counterfactual ERC-6492 account first):
SignatureValidator.isValidSignatureNowWithSideEffects(signer, hash, signature);
```

### Install (consumers)

```
yarn add github:KrystalDeFi/util-contracts
```

Add to `remappings.txt`:
```
@krystal/util-contracts/=node_modules/@krystal/util-contracts/
```

### Develop

```
npm install && forge test -vvv
```
```

- [ ] **Step 2: Commit**

```bash
cd ../util-contracts
git add README.md
git commit -m "docs: document SignatureValidator usage"
```

---

### Task 4: Install into parent (local) + swap `PrivateVaultAutomator` to `SignatureValidator`

**Files:**
- Modify: `package.json` (add dependency)
- Modify: `remappings.txt` (add remapping)
- Modify: `contracts/private-vault/core/PrivateVaultAutomator.sol:13,82,92,100`

**Interfaces:**
- Consumes: `SignatureValidator.isValidSignatureNow(address,bytes32,bytes) view returns (bool)` (Task 1).
- Produces: automator behavior unchanged in signature; validation now dual-path.

- [ ] **Step 1: Add the dependency (local path for development)**

Add to `package.json` `dependencies` (kept alphabetical near `@ethersproject`):

```json
"@krystal/util-contracts": "file:../util-contracts",
```

Then:

```bash
yarn install
```

Expected: `node_modules/@krystal/util-contracts/contracts/SignatureValidator.sol` present (symlinked). NOTE: Task 8 flips this to `github:KrystalDeFi/util-contracts#<ref>` after the repo is pushed.

- [ ] **Step 2: Add the remapping**

Append to `remappings.txt` (maps to package **root**; the `contracts/` segment is in the import path, matching the repo's `@openzeppelin/` convention):

```
@krystal/util-contracts/=node_modules/@krystal/util-contracts/
```

- [ ] **Step 3: Swap the import and call sites in `PrivateVaultAutomator.sol`**

Replace line 13:

```solidity
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
```

with:

```solidity
import { SignatureValidator } from "@krystal/util-contracts/contracts/SignatureValidator.sol";
```

Replace the three call sites (lines 82, 92, 100) — swap `SignatureChecker` for `SignatureValidator`, keeping arguments identical:

```solidity
// line 82 (_validateAgentAllowance)
require(SignatureValidator.isValidSignatureNow(IPrivateVault(vault).vaultOwner(), digest, signature), InvalidSignature());
// line 92 (_validateOrder)
require(SignatureValidator.isValidSignatureNow(actor, digest, orderSignature), InvalidSignature());
// line 100 (cancelOrder)
require(SignatureValidator.isValidSignatureNow(msg.sender, hash, signature), InvalidSignature());
```

- [ ] **Step 4: Build**

```bash
FOUNDRY_OFFLINE=true forge build --offline
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: compiles; `PrivateVaultAutomator` resolves `@krystal/util-contracts`.

- [ ] **Step 5: Run the existing smart-wallet suite to prove NO regression**

```bash
FOUNDRY_OFFLINE=true RPC_URL=https://mainnet.base.org forge test --offline \
  --match-contract "PrivateVaultAutomatorSmartWalletOwner" -vvv
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: all Phase-A tests still PASS — Coinbase (ERC-1271 leg) and wrapped-Biz (ERC-1271 leg) are unaffected; the dual-path is a strict superset.

- [ ] **Step 6: Commit**

```bash
git add package.json remappings.txt contracts/private-vault/core/PrivateVaultAutomator.sol
git commit -m "feat(private-vault): validate owner sigs via SignatureValidator (7702 dual-path)"
```

---

### Task 5: Parent UNIT test — automator accepts a 7702 owner's RAW-EOA signature

**Files:**
- Create: `test/unit/PrivateVaultAutomator7702RawSig.t.sol`

**Interfaces:**
- Consumes: `PrivateVaultAutomator` (via a local `AutomatorHarness`), `PrivateVault`, `PrivateConfigManager`, `AgentAllowanceStructHash`, `LpUniV3StructHash` (existing repo types).
- Produces: none.

- [ ] **Step 1: Write the failing test**

This is a **non-fork** unit test (runs offline, no RPC). It reuses the mock patterns from `test/unit/PrivateVaultAutomatorSmartWalletOwner.t.sol` but the 7702 wallet requires a WRAPPED hash while the owner signs the RAW digest — the exact case `SignatureChecker` rejected and `SignatureValidator` now accepts.

Create `test/unit/PrivateVaultAutomator7702RawSig.t.sol`:

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { PrivateVaultAutomator } from "../../contracts/private-vault/core/PrivateVaultAutomator.sol";
import { IPrivateVaultAutomator } from "../../contracts/private-vault/interfaces/core/IPrivateVaultAutomator.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

contract RawSigMockStrategy {
  uint256 public value;
  function setValue(uint256 _value) external { value = _value; }
}

contract RawSigAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }
  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return _hashTypedDataV4(structHash);
  }
}

/// @dev 7702 delegate that ONLY validates a signature over its own EIP-712-wrapped hash — so a RAW
///      signature fails its isValidSignature. Etched onto an EOA to give code + key at one address.
contract Wrapped7702Delegate {
  bytes4 constant MAGIC = 0x1626ba7e;
  function wrap(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Delegate:", block.chainid, address(this), hash));
  }
  function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    (address rec, ECDSA.RecoverError err, ) = ECDSA.tryRecover(wrap(hash), sig);
    return (err == ECDSA.RecoverError.NoError && rec == address(this)) ? MAGIC : bytes4(0xffffffff);
  }
}

/// @title A 7702 vault owner signing the RAW automator digest (the SignatureChecker-rejected case).
contract PrivateVaultAutomator7702RawSigTest is Test {
  RawSigAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  RawSigMockStrategy internal strategy;

  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant OWNER_PK = 0x7702BEEF;
  address internal owner7702;
  uint256 internal allowanceNonce;

  function setUp() public {
    strategy = new RawSigMockStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);

    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new RawSigAutomatorHarness(ADMIN, operators);

    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();

    owner7702 = vm.addr(OWNER_PK);
    Wrapped7702Delegate impl = new Wrapped7702Delegate();
    vm.etch(owner7702, address(impl).code); // 7702: code + key
  }

  function _deployVault() internal returns (PrivateVault vault) {
    vault = new PrivateVault();
    vault.initialize(owner7702, address(configManager), "7702 raw-sig vault");
  }

  function _agentAllowance(address vault) internal returns (bytes memory encoded, bytes32 digest) {
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory a =
      AgentAllowanceStructHash.AgentAllowance(vault, uint64(block.timestamp + allowanceNonce), uint64(block.timestamp + 3600));
    encoded = abi.encode(a);
    digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
  }

  function _orderDigest() internal view returns (bytes memory encoded, bytes32 digest) {
    LpUniV3StructHash.Order memory emptyOrder;
    encoded = abi.encode(emptyOrder);
    digest = automator.hashTypedDataV4(LpUniV3StructHash._hash(emptyOrder));
  }

  function _rawSign(bytes32 digest, uint256 pk) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    return abi.encodePacked(r, s, v);
  }

  function _multicall()
    internal view
    returns (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct)
  {
    t = new address[](1); cv = new uint256[](1); d = new bytes[](1); ct = new IPrivateCommon.CallType[](1);
    t[0] = address(strategy);
    d[0] = abi.encodeWithSelector(RawSigMockStrategy.setValue.selector, 42);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  function test_7702_rawSig_agentAllowance_success() public {
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _rawSign(digest, OWNER_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_7702_rawSig_userOrder_success() public {
    PrivateVault vault = _deployVault();
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _rawSign(digest, OWNER_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }

  function test_7702_rawSig_cancelOrder_success() public {
    _deployVault();
    bytes32 orderHash = keccak256("7702-raw-order");
    bytes memory sig = _rawSign(orderHash, OWNER_PK);
    vm.prank(owner7702);
    automator.cancelOrder(orderHash, sig);
    assertTrue(automator.isOrderCancelled(orderHash));
  }

  function test_7702_rawSig_wrongKey_reverts() public {
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory badSig = _rawSign(digest, 0xBAD5);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, badSig);
  }
}
```

- [ ] **Step 2: Run to verify (fails on old automator, passes on new)**

```bash
FOUNDRY_OFFLINE=true forge test --offline --match-contract PrivateVaultAutomator7702RawSig -vvv
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: PASS on the swapped automator (Task 4). If reverted to `SignatureChecker`, `test_7702_rawSig_*_success` would revert `InvalidSignature` — confirming the fix.

- [ ] **Step 3: Commit**

```bash
git add test/unit/PrivateVaultAutomator7702RawSig.t.sol
git commit -m "test(unit): 7702 owner raw-EOA sig accepted by automator via SignatureValidator"
```

---

### Task 6: Parent INTEGRATION test — full lifecycle with real vault wiring + 7702 owner

**Files:**
- Create: `test/integration/PrivateVaultAutomator7702Integration.t.sol`

**Interfaces:**
- Consumes: same repo types as Task 5.
- Produces: none.

**Rationale:** Task 5 isolates the signature path. This test drives the *end-to-end operator flow* — agent-allowance issuance, a real `PrivateVault.multicall` through the whitelisted-caller authorization path, order cancellation making a later execute revert — proving the composed system works with the new library and that the vault needs no redeploy.

- [ ] **Step 1: Write the failing test**

Create `test/integration/PrivateVaultAutomator7702Integration.t.sol` (non-fork). Reuse the `Wrapped7702Delegate`, `RawSigMockStrategy`, `RawSigAutomatorHarness` mock shapes from Task 5 (copy them in — the engineer may read tasks out of order; keep this file self-contained):

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { PrivateVaultAutomator } from "../../contracts/private-vault/core/PrivateVaultAutomator.sol";
import { IPrivateVaultAutomator } from "../../contracts/private-vault/interfaces/core/IPrivateVaultAutomator.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

contract IntgStrategy {
  uint256 public value;
  function setValue(uint256 _value) external { value = _value; }
}

contract IntgAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }
  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) { return _hashTypedDataV4(structHash); }
}

contract IntgWrapped7702Delegate {
  bytes4 constant MAGIC = 0x1626ba7e;
  function wrap(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Delegate:", block.chainid, address(this), hash));
  }
  function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    (address rec, ECDSA.RecoverError err, ) = ECDSA.tryRecover(wrap(hash), sig);
    return (err == ECDSA.RecoverError.NoError && rec == address(this)) ? MAGIC : bytes4(0xffffffff);
  }
}

contract PrivateVaultAutomator7702IntegrationTest is Test {
  IntgAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  IntgStrategy internal strategy;
  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant OWNER_PK = 0x7702F00D;
  address internal owner7702;
  uint256 internal allowanceNonce;

  function setUp() public {
    strategy = new IntgStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);
    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new IntgAutomatorHarness(ADMIN, operators);
    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();
    owner7702 = vm.addr(OWNER_PK);
    IntgWrapped7702Delegate impl = new IntgWrapped7702Delegate();
    vm.etch(owner7702, address(impl).code);
  }

  function _vault() internal returns (PrivateVault v) {
    v = new PrivateVault();
    v.initialize(owner7702, address(configManager), "7702 integration vault");
  }

  function _multicall(uint256 val)
    internal view
    returns (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct)
  {
    t = new address[](1); cv = new uint256[](1); d = new bytes[](1); ct = new IPrivateCommon.CallType[](1);
    t[0] = address(strategy);
    d[0] = abi.encodeWithSelector(IntgStrategy.setValue.selector, val);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  function _rawSign(bytes32 digest) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);
    return abi.encodePacked(r, s, v);
  }

  // Reusable agent allowance signed once, replayed on multiple operator executions until expiry.
  function test_lifecycle_reusableAllowance_multipleExecutions() public {
    PrivateVault vault = _vault();
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory a =
      AgentAllowanceStructHash.AgentAllowance(address(vault), uint64(block.timestamp + 1), uint64(block.timestamp + 3600));
    bytes memory encoded = abi.encode(a);
    bytes32 digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
    bytes memory sig = _rawSign(digest);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall(7);
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 7);

    (t, cv, d, ct) = _multicall(9);
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 9); // same signature reused
  }

  // Non-operator cannot execute even with a valid owner signature.
  function test_nonOperator_reverts() public {
    PrivateVault vault = _vault();
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory a =
      AgentAllowanceStructHash.AgentAllowance(address(vault), uint64(block.timestamp + 1), uint64(block.timestamp + 3600));
    bytes memory encoded = abi.encode(a);
    bytes32 digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
    bytes memory sig = _rawSign(digest);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall(7);
    vm.prank(address(0xBEEF));
    vm.expectRevert();
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
  }

  // Cancelling an order makes a subsequent execute with that order revert.
  function test_cancelledOrder_blocksExecution() public {
    PrivateVault vault = _vault();
    LpUniV3StructHash.Order memory emptyOrder;
    bytes memory encodedOrder = abi.encode(emptyOrder);
    bytes32 digest = automator.hashTypedDataV4(LpUniV3StructHash._hash(emptyOrder));
    bytes memory sig = _rawSign(digest);

    vm.prank(owner7702);
    automator.cancelOrder(digest, sig);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall(5);
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.OrderCancelled.selector);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
  }
}
```

- [ ] **Step 2: Run**

```bash
FOUNDRY_OFFLINE=true forge test --offline --match-contract PrivateVaultAutomator7702Integration -vvv
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: PASS — 3 tests. (`OrderCancelled()` is declared in `IPrivateVaultAutomator` line 10, and `_validateOrder` reverts it via `require(!_cancelledOrder[digest], OrderCancelled())` at `PrivateVaultAutomator.sol:93` — so the `vm.expectRevert(IPrivateVaultAutomator.OrderCancelled.selector)` is correct as written.)

- [ ] **Step 3: Commit**

```bash
git add test/integration/PrivateVaultAutomator7702Integration.t.sol
git commit -m "test(integration): 7702 owner operator lifecycle via SignatureValidator"
```

---

### Task 7: Parent FORK test — real Biz bytecode accepts a RAW-EOA 7702 signature + CI + memory

**Files:**
- Modify: `test/integration/PrivateVaultBizFork.t.sol` (add a raw-EOA-digest test)
- Modify: `.github/workflows/pr-test.yaml:55` (add new contracts to the osaka match)
- Modify: `/Users/maddie/.claude/projects/-Users-maddie-Desktop-Work-krystal-archive-KYRDTeam-krystal-vault-contracts-v2/memory/smart-wallet-owner-test-suite.md`

**Interfaces:**
- Consumes: existing `PrivateVaultBizForkTest` harness (`bizAccount`, `BIZ_OWNER_PK`, `_agentAllowance`, `_multicall`, `_skipUnlessLive`).
- Produces: none.

**Rationale:** The existing Biz fork test signs the *wrapped* hash (ERC-1271 leg). This adds the **new** leg: the real Biz 7702 account's key signs the automator's *raw* digest — `SignatureChecker` rejected this; `SignatureValidator` accepts it via ECDSA. Coinbase has no EOA key equal to its own address, so its fork test stays wrapped-only (proves the ERC-1271 leg still works post-swap) — no change needed there.

- [ ] **Step 1: Add the raw-EOA test to `PrivateVaultBizFork.t.sol`**

Add these helper + tests inside `PrivateVaultBizForkTest` (after `test_fork_biz7702_wrongSigner_reverts`):

```solidity
  // Sign the RAW automator digest with the delegating EOA's key (no Biz EIP-712 wrap).
  // SignatureChecker rejected this; SignatureValidator accepts it via the ECDSA leg.
  function _rawSignAsBiz(bytes32 digest, uint256 pk) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    return abi.encodePacked(r, s, v);
  }

  function test_fork_biz7702_rawEoaSig_agentAllowance() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _rawSignAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_fork_biz7702_rawEoaSig_userOrder() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _rawSignAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }
```

- [ ] **Step 2: Run the Biz fork test (needs a mainnet RPC)**

```bash
MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com \
  forge test --match-contract PrivateVaultBizFork -vvv
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: the two new `rawEoaSig` tests PASS (proving the real Biz account's raw signature is now accepted); prior wrapped tests still PASS. Without `MAINNET_RPC_URL` they self-skip.

- [ ] **Step 3: Confirm the Coinbase fork test still passes (ERC-1271 leg unchanged)**

```bash
RPC_URL=https://mainnet.base.org forge test --match-contract PrivateVaultSmartWalletOwnerFork -vvv
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: PASS or self-skip; no regression.

- [ ] **Step 4: Update the CI osaka step match list**

In `.github/workflows/pr-test.yaml`, line 55, extend the `--match-contract` regex to include the two new contracts:

```yaml
            --match-contract "PrivateVaultAutomatorSmartWalletOwner|PrivateVaultAutomatorPasskeyOwner|PrivateVaultSmartWalletOwnerFork|PrivateVaultBizFork|PrivateVaultAutomator7702RawSig|PrivateVaultAutomator7702Integration" -vvv
```

- [ ] **Step 5: Update memory**

Append to `smart-wallet-owner-test-suite.md` a note: automator now validates via `@krystal/util-contracts` `SignatureValidator` (dual-path ERC-1271 OR ECDSA); new tests `PrivateVaultAutomator7702RawSig` (unit), `PrivateVaultAutomator7702Integration` (integration), and Biz-fork `rawEoaSig` cases prove the raw-EOA-7702 signature (previously `SignatureChecker`-rejected) is accepted. Vault needs no redeploy — only the automator.

- [ ] **Step 6: Commit**

```bash
git add test/integration/PrivateVaultBizFork.t.sol .github/workflows/pr-test.yaml
git commit -m "test(fork): real Biz 7702 raw-EOA sig accepted; wire CI + memory"
```

---

### Task 8: Publish util-contracts + switch parent to the GitHub dependency

**Files:**
- Modify: `package.json` (flip `file:` → `github:`)

**Interfaces:** none.

**REQUIRES USER AUTHORIZATION:** pushing `util-contracts` to GitHub is an outward-facing action. Do NOT push without an explicit go-ahead.

- [ ] **Step 1: Push util-contracts (after user confirms)**

```bash
cd ../util-contracts
git push -u origin HEAD
```

Note the pushed branch/tag ref (e.g. `main` or a `v0.1.0` tag).

- [ ] **Step 2: Flip the parent dependency to the GitHub ref**

In `package.json`, change:

```json
"@krystal/util-contracts": "file:../util-contracts",
```

to (pin to the pushed ref):

```json
"@krystal/util-contracts": "github:KrystalDeFi/util-contracts#<pushed-ref>",
```

- [ ] **Step 3: Reinstall and re-run the swapped suite**

```bash
yarn install
FOUNDRY_OFFLINE=true forge test --offline --match-contract "PrivateVaultAutomator7702RawSig|PrivateVaultAutomator7702Integration|PrivateVaultAutomatorSmartWalletOwner" -vvv
```

(Run with `dangerouslyDisableSandbox: true`.) Expected: identical results to the `file:` install — resolution now comes from `node_modules/@krystal/util-contracts` fetched from GitHub.

- [ ] **Step 4: Commit**

```bash
git add package.json yarn.lock
git commit -m "chore: consume @krystal/util-contracts from GitHub"
```

---

## Notes on rollout (post-implementation, out of plan scope)

Deploying the change to production is separate work: deploy the new `PrivateVaultAutomator`, grant it `OPERATOR_ROLE`, whitelist it in the target `PrivateConfigManager` (`setWhitelistCallers`), and repoint the backend (`agentAllowance.ts` `resolveVaultAutomator`) at the new address. The existing vault and its Biz/Coinbase owner are untouched — no vault migration and no owner re-signing beyond the new automator domain, which is the whole point of touching only the automator.
