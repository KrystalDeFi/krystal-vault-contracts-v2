import { ethers } from "ethers";
import * as hre from "hardhat";

export const Permit = [
  {
    name: "owner",
    type: "address",
  },
  {
    name: "spender",
    type: "address",
  },
  {
    name: "value",
    type: "uint256",
  },
  {
    name: "nonce",
    type: "uint256",
  },
  {
    name: "deadline",
    type: "uint256",
  },
];

export const evm_snapshot = async function () {
  return await hre.network.provider.request({
    method: "evm_snapshot",
    params: [],
  });
};

export const evm_revert = async function (snapshotId: any) {
  return await hre.network.provider.request({
    method: "evm_revert",
    params: [snapshotId],
  });
};

export const getOpenzeppelinDefaultImplementation = async (provider: ethers.Provider, address: string) => {
  let data = await provider.getStorage(address, "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
  return "0x" + data.slice(26, 66);
};

export const getOpenzeppelinDefaultAdmin = async (provider: ethers.Provider, address: string) => {
  let data = await provider.getStorage(address, "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103");
  return "0x" + data.slice(26, 66);
};

export const sleep = (timeout: number) => {
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve("ok");
    }, timeout);
  });
};

export const sortObject = (obj: Record<string, any>) => {
  let res: Record<string, any> = {};
  Object.keys(obj)
    .sort((a, b) => (a > b ? 1 : -1))
    .forEach((k: string) => {
      res[k] = obj[k];
    });
  return res;
};
