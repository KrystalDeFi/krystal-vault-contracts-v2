#!/bin/bash


red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
magenta='\033[0;35m'
cyan='\033[0;36m'
clear='\033[0m'

function log_info() {
    echo -e "${magenta}$1${clear}"
}

function log_error() {
    echo -e "${red}$1${clear}"
}

# Get the contract name from argv if provided, otherwise use default
CONTRACT_NAME=${1:-VaultFuzzerWithSwap}
log_info "[+] Doing echidna test for contract: $CONTRACT_NAME"

log_info "[+] Clean the out directory"
rm -rf out/

log_info "[+] Clean the echidna-fuzzer contract in the contracts directory"
rm -rf contracts/echidna-fuzzer

log_info "[+] Move the hardhat.config.ts file to hardhat.config.ts.disabled to use foundry as the compiler only"
mv hardhat.config.ts hardhat.config.ts.disabled

log_info "[+] Disable the sanityCheck in the LpValidator.sol file"
cp contracts/strategies/lpUniV3/LpValidator.sol contracts/strategies/lpUniV3/LpValidator.sol.tmp
sed -i '' 's/function validatePriceSanity(address pool) external view override {/function validatePriceSanity(address pool) external view override { return; \/\/ to disable the sanityCheck for debugging purposes/g' contracts/strategies/lpUniV3/LpValidator.sol

log_info "[+] Replace the out directory in foundry.toml"
cp foundry.toml foundry.toml.tmp
sed -i '' 's/out = '\''artifacts'\''/out = '\''out\/'\''/g' foundry.toml

log_info "[+] Copy the echidna-fuzzer contract to the contracts directory"
mkdir contracts/echidna-fuzzer/
find test/echidna-fuzzer -type f -not -name "*.t.sol" -exec cp -v {} contracts/echidna-fuzzer/ \;

log_info "[+] Comment out all console.log lines in the contracts"
find contracts/ -type f -name "*.sol" -exec sed -i '' 's/^[[:space:]]*console\.log/\/\/ console\.log/g' {} \;

log_info "[+] Comment out all forge-test-only lines in the contracts"
find contracts/ -type f -name "*.sol" -exec sed -i '' 's/^[[:space:]]*.*\/\/forge-test-only.*$/\/\/ &/g' {} \;

log_info "[+] Comment out all forge-std lines in the contracts"
find contracts/ -type f -name "*.sol" -exec sed -i '' 's/^import[[:space:]]\"forge-std\/.*/\/\/ &/g' {} \;

export ECHIDNA_RPC_URL="https://rpc-node-lb.krystal.app/?chain_id=1&debug_trace_only=true"
# https://rpc.ankr.com/eth/431b8fcced2be35b5b757fc266beb9f70373e23bc8bd715c31759b1fdf50ad8a

log_info "[+] Run the echidna test: echidna ./ --config test/echidna-fuzzer/config.yaml --contract $CONTRACT_NAME"
echidna ./ --config test/echidna-fuzzer/config.yaml --contract $CONTRACT_NAME

log_info "[+] Restore the hardhat.config.ts file"
mv hardhat.config.ts.disabled hardhat.config.ts

log_info "[+] Restore the foundry.toml file"
mv foundry.toml.tmp foundry.toml

log_info "[+] Restore the LpValidator.sol file"
mv contracts/strategies/lpUniV3/LpValidator.sol.tmp contracts/strategies/lpUniV3/LpValidator.sol


log_info "[+] Remove the echidna-fuzzer contract in the contracts directory"
rm -rf contracts/echidna-fuzzer

