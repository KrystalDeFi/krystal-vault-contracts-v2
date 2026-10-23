# Solidity API

## IAeroLeafVoter

Aero's per-chain LeafVoter: settles gauge emissions and mints them as its receipt token (xAERO), which the
        emissions handler then delivers.

### isActivated

```solidity
function isActivated(address gauge) external view returns (bool)
```

Whether `gauge` is activated; an inactive gauge earns no emissions

### RECEIPT_TOKEN

```solidity
function RECEIPT_TOKEN() external view returns (address)
```

### EMISSIONS_HANDLER

```solidity
function EMISSIONS_HANDLER() external view returns (address)
```

Leaf chains' handler transfers the receipt token to the recipient; Base's redeems it for AERO instead

