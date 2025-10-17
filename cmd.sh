#!/bin/sh

usage="yarn <deploy,deploy-private,test> [-h] [-c <eth,bsc,polygon,arbitrum,optimism,base,berachain,ronin,hyperevm>] [-n <mainnet,testnet>] -- to run test on specific chain and network

where:
    -h  show this help text
    -c  which chain to run, supported <eth,bsc,polygon,arbitrum,optimism,base,berachain,ronin,hyperevm>
    -n  which network to run, supported <mainnet,testnet>
    -f  specific test to run if any"

# Default chain and network
CHAIN="eth"
NETWORK="testnet"
CMD="test"

while getopts ":hc:n:f:x:" option; do
  case $option in
    h) 
      echo "$usage"
      exit
      ;;
    c) 
      if [[ ! "$OPTARG" =~ ^(eth|bsc|polygon|arbitrum|optimism|base|berachain|ronin|hyperevm)$ ]]; then
          printf "invalid value for -%s\n" "$option" >&2
          echo "$usage" >&2
          exit 1
      fi
      CHAIN=$OPTARG;;      
    n) 
      if [[ ! "$OPTARG" =~ ^(mainnet|testnet)$ ]]; then
          printf "invalid value for -%s\n" "$option" >&2
          echo "$usage" >&2
          exit 1
      fi
      NETWORK=$OPTARG;;
    f) 
      FILE=$OPTARG;;
    x)
      CMD=$OPTARG;;
    :) 
      printf "missing argument for -%s\n" "$OPTARG" >&2
      echo "$usage" >&2
      exit 1
      ;;
    *)                               
      printf "illegal option: -%s\n" "$OPTARG" >&2
      echo "$usage" >&2
      exit 1
      ;;
  esac
done

if [ $CMD == "test" ]; then
  if [ -n "$FILE" ]; then
    CHAIN=$CHAIN NETWORK=$NETWORK yarn hardhat test --no-compile --network hardhat $FILE
  else
    echo "Running all tests..."
    CHAIN=$CHAIN NETWORK=$NETWORK yarn hardhat test --no-compile --network hardhat
  fi
elif [ $CMD == "deploy" ]; then
  CHAIN=$CHAIN NETWORK=$NETWORK yarn hardhat run scripts/deployer.ts --network "$CHAIN"_"$NETWORK"
elif [ $CMD == "deploy-private" ]; then
  CHAIN=$CHAIN NETWORK=$NETWORK yarn hardhat run scripts/deployer-private.ts --network "$CHAIN"_"$NETWORK"
fi
