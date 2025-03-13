import { ethers } from "hardhat";
import { parseEther } from "ethers";
import * as chai from "chai";
import { expect } from "chai";
import chaiAsPromised from "chai-as-promised";

import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

import { TestERC20, Vault, VaultFactory } from "../typechain-types";

import { TestConfig } from "../configs/testConfig";
import { NetworkConfig } from "../configs/networkConfig";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

chai.use(chaiAsPromised);

describe("VaultFactory", () => {
  async function testFixture() {
    let owner: HardhatEthersSigner, alice: HardhatEthersSigner, bob: HardhatEthersSigner;
    let implementation: Vault;
    let factory: VaultFactory;
    let token0: TestERC20;
    let token1: TestERC20;
    let weth: TestERC20;

    [owner, alice, bob] = await ethers.getSigners();

    implementation = await ethers.deployContract("Vault");

    await implementation.waitForDeployment();

    const implementationAddress = await implementation.getAddress();
    console.log("implementation deployed at: ", implementationAddress);

    const configManager = await ethers.deployContract("ConfigManager");
    await configManager.waitForDeployment();

    const configManagerAddress = await configManager.getAddress();
    console.log("configManager deployed at: ", configManagerAddress);

    token0 = await ethers.deployContract("TestERC20", [parseEther("1000000")]);
    await token0.waitForDeployment();
    token1 = await ethers.deployContract("TestERC20", [parseEther("1000000")]);
    await token1.waitForDeployment();
    weth = await ethers.deployContract("TestERC20", [parseEther("1000000")]);
    await weth.waitForDeployment();
    console.log("token0: ", await token0.getAddress());
    console.log("token1: ", await token1.getAddress());
    console.log("weth: ", await weth.getAddress());

    await token0.transfer(await alice.getAddress(), parseEther("1000"));
    await token1.transfer(await alice.getAddress(), parseEther("1000"));
    await weth.transfer(await alice.getAddress(), parseEther("1000"));

    factory = await ethers.deployContract("VaultFactory", [
      weth.target,
      configManagerAddress,
      implementationAddress,
      NetworkConfig.base_mainnet.automatorAddress,
      NetworkConfig.base_mainnet.platformFeeRecipient,
      NetworkConfig.base_mainnet.platformFeeBasisPoint,
    ]);

    await factory.waitForDeployment();
    console.log("factory deployed at: ", await factory.getAddress());

    return { owner, alice, bob, factory, token0, token1, weth };
  }

  it("Should create a new vault", async () => {
    const { owner, factory } = await loadFixture(testFixture);

    console.log(owner.address, factory.target);
  });

  it("Should failed to create a new vault", async () => {
    const { owner, factory } = await loadFixture(testFixture);

    console.log(owner.address, factory.target);
  });
});
