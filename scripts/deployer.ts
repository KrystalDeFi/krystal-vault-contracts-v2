import { convertToAddressObject, deploy } from "./deployLogic";
import { network } from "hardhat";
import { sortObject } from "./helpers";
import * as fs from "fs";

let contracts: Record<string, Record<string, string>> = {};
let contractsFile = `${__dirname}/../contracts.json`;

try {
  const data = fs.readFileSync(contractsFile, "utf8");
  contracts = JSON.parse(data);
} catch {
  contracts = {};
}

deploy(contracts[network.name])
  .then((deployedContracts) => {
    // Save contracts' addresses
    contracts[network.name] = convertToAddressObject(deployedContracts);
    const json = JSON.stringify(sortObject(contracts), null, 2) + "\n";
    fs.writeFileSync(contractsFile, json, "utf8");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
