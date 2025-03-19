# Krystal Vault Contracts

This repository contains the smart contracts for the Krystal Vault. The contracts are written in Solidity and are
designed to work with the Ethereum blockchain and other EVM-compatible chains. The contracts should work well with all
Uniswap V3 Liquidity Pool types.

## Table of Contents

- [Krystal Vault Contracts](#krystal-vault-contracts)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [Usage](#usage)
    - [Compile](#compile)
    - [Test](#test)
    - [Deploy](#deploy)
  - [Deployment](#deployment)
  - [Contracts](#contracts)
  - [Events](#events)

## Installation

To install the dependencies, run:

```sh
yarn install
```

## Usage

### Compile

To compile the smart contracts, run:

```sh
yarn compile
```

### Test

To run the tests, use:

```sh
yarn test
```

### Deploy

To deploy the contracts, use:

```sh
yarn deploy -c base -n mainnet
```

## Deployment

The deployment scripts logic are located in the `scripts` directory. The main deployment logic script is
`deployLogic.ts`. The main deployment script is `cmd.sh`. The deployment script uses the `hardhat` framework to deploy
the contracts.

## Contracts

The main contracts in this repository are:

## Events

The contracts emit various events. Some of the key events are:

## High Level Design
![Screenshot 2025-03-19 at 14 40 52](https://github.com/user-attachments/assets/66023d25-b095-47af-800c-35f87262093d)


