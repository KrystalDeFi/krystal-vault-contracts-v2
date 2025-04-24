#!/bin/bash

echo "[+] Clean the echidna-fuzzer contract in the contracts directory"
rm -rf contracts/echidna-fuzzer

echo "[+] Move the foundry.toml file to foundry.toml.disabled to use hardhat as the compiler only"
mv foundry.toml foundry.toml.disabled

echo "[+] Copy the echidna-fuzzer contract to the contracts directory"
mkdir contracts/echidna-fuzzer/
find test/echidna-fuzzer -type f -not -name "*.forge.sol" -exec cp -v {} contracts/echidna-fuzzer/ \;

echo "[+] Comment out all console.log lines in the contracts"
find contracts/echidna-fuzzer -type f -name "*.sol" -exec sed -i '' 's/^[[:space:]]*console\.log/\/\/ console\.log/g' {} \;

echo "[+] Comment out all forge-test-only lines in the contracts"
find contracts/echidna-fuzzer -type f -name "*.sol" -exec sed -i '' 's/^[[:space:]]*.*\/\/forge-test-only.*$/\/\/ &/g' {} \;

echo "[+] Run the echidna test: echidna ./ --config test/echidna-fuzzer/config.yaml --contract VaultFuzzer"
echidna ./ --config test/echidna-fuzzer/config.yaml --contract VaultFuzzer

echo "[+] Restore the foundry.toml file"
mv foundry.toml.disabled foundry.toml

echo "[+] Remove the echidna-fuzzer contract in the contracts directory"
rm -rf contracts/echidna-fuzzer
