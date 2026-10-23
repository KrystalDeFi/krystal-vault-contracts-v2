# Solidity API

## IAeroEmissionsHandler

Aero's leaf-chain emissions handler, which pays emissions in the receipt token. Base's (root) handler redeems
        them for AERO instead and has no `RECEIPT_TOKEN()`.

### RECEIPT_TOKEN

```solidity
function RECEIPT_TOKEN() external view returns (address)
```

