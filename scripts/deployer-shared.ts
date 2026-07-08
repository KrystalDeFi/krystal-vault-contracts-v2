import { convertToAddressObject, deploy } from "./deployLogic-shared";
import { network } from "hardhat";
import { sortObject } from "./helpers";
import * as fs from "fs";

let contracts: Record<string, Record<string, string>> = {};
let contractsFile = `${__dirname}/../contracts-shared.json`;

try {
  const data = fs.readFileSync(contractsFile, "utf8");
  contracts = JSON.parse(data);
} catch {
  contracts = {};
}

let publicContracts: Record<string, Record<string, string>> = {};
try {
  const data = fs.readFileSync(`${__dirname}/../contracts.json`, "utf8");
  publicContracts = JSON.parse(data);
} catch {
  publicContracts = {};
}

const existingContracts = {
  ...contracts[network.name],
  lpFeeTaker: publicContracts[network.name]?.["lpFeeTaker"],
};

deploy(existingContracts)
  .then((deployedContracts) => {
    contracts[network.name] = convertToAddressObject(deployedContracts);
    const json = JSON.stringify(sortObject(contracts), null, 2) + "\n";
    fs.writeFileSync(contractsFile, json, "utf8");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
