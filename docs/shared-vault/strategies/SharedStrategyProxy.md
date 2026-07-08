# Solidity API

## SharedStrategyProxy

Upgradeable proxy for a SharedVault strategy type.

        Storage-collision safety
        ─────────────────────────
        SharedVault calls strategies via delegatecall, meaning the proxy's code runs in
        SharedVault's storage context. Storing the implementation address in a regular
        storage slot would collide with SharedVault's own layout.

        This proxy avoids collision by keeping the beacon address as an `immutable` —
        immutables are embedded in contract bytecode, not in storage, so they are readable
        in any delegatecall context without touching storage slots.

        The beacon (a separate contract) stores the implementation in its own storage.
        Fetching it is an external call, which always executes in the beacon's context.

        Call flow
        ─────────
        SharedVault  --delegatecall-->  SharedStrategyProxy (beacon read, then delegatecall)
                                        └──delegatecall──>  StrategyImpl (runs as vault)

        For getPositionAmounts (regular call, not delegatecall):
        SharedVault  --call-->  SharedStrategyProxy (beacon read, then delegatecall)
                                └──delegatecall──>  StrategyImpl (runs as proxy)

_Deploy one proxy per strategy type (V3, Aerodrome, PancakeV3, V4).
     Whitelist the proxy address in SharedConfigManager — never needs re-whitelisting on upgrade.
     To upgrade: call SharedStrategyBeacon.setImplementation(newImpl)._

### beacon

```solidity
contract SharedStrategyBeacon beacon
```

The beacon that holds the current implementation address.
        Stored as immutable to avoid storage-collision with SharedVault when delegatecalled.

### constructor

```solidity
constructor(address _beacon) public
```

### _checkWithdrawPermission

```solidity
function _checkWithdrawPermission() internal view
```

_Only the beacon owner can sweep accidentally stuck tokens._

### fallback

```solidity
fallback() external payable
```

_Forwards every call to the current implementation via delegatecall.
     Uses raw assembly so return data and reverts are propagated byte-for-byte._

### receive

```solidity
receive() external payable
```

_Accept ETH so accidentally sent native tokens can be recovered via sweepNativeToken()._

