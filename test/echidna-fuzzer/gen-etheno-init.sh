#!/bin/bash
# Generates etheno-init.json for echidna's initialize config.
# Deploys SharedVaultCoreDeployer and SharedVaultStrategyDeployer
# at deterministic addresses so the fuzzer can read from them.
#
# Usage: bash test/echidna-fuzzer/gen-etheno-init.sh
# Requires: forge build output in out/

set -euo pipefail

CORE_ADDR="0x00000000000000000000000000000000DE010661"
STRAT_ADDR="0x00000000000000000000000000000000De010662"
DEPLOYER="0x0000000000000000000000000000000000010000"

get_bytecode() {
  local sol_file="$1"
  local contract="$2"
  python3 -c "
import json
with open('out/${sol_file}/${contract}.json') as f:
    obj = json.load(f)
bc = obj.get('bytecode', {}).get('object', '')
if not bc.startswith('0x'):
    bc = '0x' + bc
print(bc)
"
}

CORE_BC=$(get_bytecode "SharedVaultStrategyDeployer.sol" "SharedVaultCoreDeployer")
STRAT_BC=$(get_bytecode "SharedVaultStrategyDeployer.sol" "SharedVaultStrategyDeployer")

cat > test/echidna-fuzzer/etheno-init.json <<EOFJ
[
  {
    "event": "ContractCreated",
    "from": "${DEPLOYER}",
    "contract_address": "${CORE_ADDR}",
    "gas_used": "0xffffff",
    "gas_price": "0x1",
    "data": "${CORE_BC}",
    "value": "0x0"
  },
  {
    "event": "ContractCreated",
    "from": "${DEPLOYER}",
    "contract_address": "${STRAT_ADDR}",
    "gas_used": "0xffffff",
    "gas_price": "0x1",
    "data": "${STRAT_BC}",
    "value": "0x0"
  }
]
EOFJ

echo "Generated test/echidna-fuzzer/etheno-init.json"
echo "  CoreDeployer  @ ${CORE_ADDR} ($(echo -n "$CORE_BC" | wc -c) chars)"
echo "  StratDeployer @ ${STRAT_ADDR} ($(echo -n "$STRAT_BC" | wc -c) chars)"
