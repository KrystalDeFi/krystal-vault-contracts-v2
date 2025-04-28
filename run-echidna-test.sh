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

log_info "[+] Clean the echidna-fuzzer contract in the contracts directory"
rm -rf contracts/echidna-fuzzer

log_info "[+] Move the foundry.toml file to foundry.toml.disabled to use hardhat as the compiler only"
mv foundry.toml foundry.toml.disabled

log_info "[+] Copy the echidna-fuzzer contract to the contracts directory"
mkdir contracts/echidna-fuzzer/
find test/echidna-fuzzer -type f -not -name "*.t.sol" -exec cp -v {} contracts/echidna-fuzzer/ \;

log_info "[+] Comment out all console.log lines in the contracts"
find contracts/ -type f -name "*.sol" -exec sed -i '' 's/^[[:space:]]*console\.log/\/\/ console\.log/g' {} \;

log_info "[+] Comment out all forge-test-only lines in the contracts"
find contracts/ -type f -name "*.sol" -exec sed -i '' 's/^[[:space:]]*.*\/\/forge-test-only.*$/\/\/ &/g' {} \;

log_info "[+] Comment out all forge-std lines in the contracts"
find contracts/ -type f -name "*.sol" -exec sed -i '' 's/^import[[:space:]]\"forge-std\/.*/\/\/ &/g' {} \;

export ECHIDNA_RPC_URL=https://rpc.ankr.com/eth/431b8fcced2be35b5b757fc266beb9f70373e23bc8bd715c31759b1fdf50ad8a
export ECHIDNA_RPC_BLOCK=22365182 

log_info "[+] Run the echidna test: echidna ./ --config test/echidna-fuzzer/config.yaml --contract VaultFuzzer"
echidna ./ --config test/echidna-fuzzer/config.yaml --contract VaultFuzzer

log_info "[+] Restore the foundry.toml file"
mv foundry.toml.disabled foundry.toml

log_info "[+] Remove the echidna-fuzzer contract in the contracts directory"
rm -rf contracts/echidna-fuzzer
