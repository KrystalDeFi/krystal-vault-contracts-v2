import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { parseEther } from "ethers";
import { ethers } from "hardhat";

import {
  StructHashEncoder,
  KrystalVault,
  KrystalVaultAutomator,
  KrystalVaultFactory,
  TestERC20,
} from "../typechain-types";

import { last } from "lodash";
import { NetworkConfig } from "../configs/networkConfig";
import { TestConfig } from "../configs/testConfig";
import { getMaxTick, getMinTick } from "../helpers/univ3";
import { blockNumber } from "../helpers/vm";
import { mockOrder } from "./MockOrder";
import { expect } from "chai";

describe("KrystalVaultAutomator", () => {
  let alice: HardhatEthersSigner, bob: HardhatEthersSigner;
  let implementation: KrystalVault;
  let factory: KrystalVaultFactory;
  let vault: KrystalVault;
  let token0: TestERC20;
  let token1: TestERC20;
  let nfpmAddr = TestConfig.base_mainnet.nfpm;
  let automator: KrystalVaultAutomator;
  let operator: HardhatEthersSigner;
  let abiEncodedOrder: string;
  let orderSignature: string;
  let domain: any;

  beforeEach(async () => {
    [alice, bob, operator] = await ethers.getSigners();

    implementation = await ethers.deployContract("KrystalVault");

    await implementation.waitForDeployment();
    console.log("implementation deployed at: ", await implementation.getAddress());

    const optimalSwapper = await ethers.deployContract("PoolOptimalSwapper");
    await optimalSwapper.waitForDeployment();
    console.log("optimalSwapper deployed at: ", await optimalSwapper.getAddress());

    automator = await ethers.deployContract("KrystalVaultAutomator", [operator]);
    await automator.waitForDeployment();
    console.log("automator deployed at: ", await automator.getAddress());

    factory = await ethers.deployContract("KrystalVaultFactory", [
      NetworkConfig.base_mainnet.uniswapV3Factory,
      implementation,
      automator,
      optimalSwapper,
      NetworkConfig.base_mainnet.platformFeeRecipient,
      NetworkConfig.base_mainnet.platformFeeBasisPoint,
    ]);

    await factory.waitForDeployment();
    console.log("factory deployed at: ", await factory.getAddress());

    token0 = await ethers.deployContract("TestERC20", [parseEther("1000000")]);
    await token0.waitForDeployment();
    token1 = await ethers.deployContract("TestERC20", [parseEther("1000000")]);
    await token1.waitForDeployment();
    const t0Addr = await token0.getAddress();
    const t1Addr = await token1.getAddress();
    if (t1Addr.toLowerCase() < t0Addr.toLowerCase()) {
      [token0, token1] = [token1, token0];
    }

    console.log("token0: ", await token0.getAddress());
    console.log("token1: ", await token1.getAddress());

    await token0.transfer(alice, parseEther("1000"));
    await token1.transfer(alice, parseEther("1000"));

    const nfpm = await ethers.getContractAt("INonfungiblePositionManager", nfpmAddr, await ethers.provider.getSigner());
    await nfpm.createAndInitializePoolIfNecessary(
      token0,
      token1,
      3000,
      "79228162514264337593543950336", // initial price = 1
    );

    await token0.connect(alice).approve(factory, parseEther("1000"));
    await token1.connect(alice).approve(factory, parseEther("1000"));
    const tx = await factory.connect(alice).createVault({
      owner: alice.address,
      nfpm: nfpm,
      mintParams: {
        token0: token0,
        token1: token1,
        fee: 3000,
        tickLower: getMinTick(60),
        tickUpper: getMaxTick(60),
        amount0Desired: parseEther("2"),
        amount1Desired: parseEther("2"),
        amount0Min: parseEther("0.9"),
        amount1Min: parseEther("0.9"),
        recipient: alice,
        deadline: (await blockNumber()) + 100,
      },
      ownerFeeBasisPoint: NetworkConfig.base_mainnet.ownerFeeBasisPoint || 50,
      name: "Vault Name",
      symbol: "VAULT",
    });

    const receipt = await tx.wait();
    // @ts-ignore
    const vaultAddress = last(receipt?.logs)?.args?.[1];
    vault = await ethers.getContractAt("KrystalVault", vaultAddress);

    token0.transfer(bob, parseEther("1000"));
    token1.transfer(bob, parseEther("1000"));

    await token0.connect(bob).approve(factory, parseEther("1000"));
    await token1.connect(bob).approve(factory, parseEther("1000"));
    await factory.connect(bob).createVault({
      owner: bob.address,
      nfpm: nfpm,
      mintParams: {
        token0: token0,
        token1: token1,
        fee: 3000,
        tickLower: getMinTick(60),
        tickUpper: getMaxTick(60),
        amount0Desired: parseEther("100"),
        amount1Desired: parseEther("100"),
        amount0Min: parseEther("0.9"),
        amount1Min: parseEther("0.9"),
        recipient: alice,
        deadline: (await blockNumber()) + 100,
      },
      ownerFeeBasisPoint: NetworkConfig.base_mainnet.ownerFeeBasisPoint || 50,
      name: "Vault Name",
      symbol: "VAULT",
    });

    const network = await ethers.provider.getNetwork();
    const sEncoder = await ethers.deployContract("StructHashEncoder");
    mockOrder.message.nfpmAddress = nfpmAddr;
    mockOrder.message.chainId = network.chainId.toString();
    abiEncodedOrder = await sEncoder.encode(mockOrder.message);
    domain = {
      name: "V3AutomationOrder",
      version: "4.0",
      chainId: network.chainId,
      verifyingContract: await automator.getAddress(),
    };
    orderSignature = await alice.signTypedData(domain, mockOrder.types, mockOrder.message);
  });

  it("should execute automated order", async () => {
    await automator.connect(operator).executeRebalance({
      vault: vault,
      newTickLower: -300,
      newTickUpper: 600,
      decreaseAmount0Min: 0,
      decreaseAmount1Min: 0,
      amount0Min: 0,
      amount1Min: 0,
      automatorFee: 100,
      abiEncodedUserOrder: abiEncodedOrder,
      orderSignature: orderSignature,
    });
    {
      const state = await vault.state();
      expect(state.currentTickLower).to.be.equal(-300);
      expect(state.currentTickUpper).to.be.equal(600);
      const pos = await vault.getBasePosition();
      expect(pos[1]).to.be.equal(BigInt("2346332740274337647"));
      expect(pos[2]).to.be.equal(BigInt("1651417881126655081"));
    }
    await automator.connect(operator).executeCompound(vault, 0, 0, 0, abiEncodedOrder, orderSignature);
    {
      const state = await vault.state();
      const pos = await vault.getBasePosition();
      expect(pos[1]).to.be.equal(BigInt("2346332740274337653"));
      expect(pos[2]).to.be.equal(BigInt("1651417881126655094"));
    }
    const aliceBalance0Before = await token0.balanceOf(alice);
    const aliceBalance1Before = await token1.balanceOf(alice);
    await automator.connect(operator).executeExit(vault, 0, 0, 0, abiEncodedOrder, orderSignature);
    const aliceBalance0After = await token0.balanceOf(alice);
    const aliceBalance1After = await token1.balanceOf(alice);
    expect(aliceBalance0After - aliceBalance0Before).to.be.equal("2346332740274337653");
    expect(aliceBalance1After - aliceBalance1Before).to.be.equal("1651417881126655102");
  });
  it("shouldn't execute if not operator", async () => {
    await expect(
      automator.connect(alice).executeRebalance({
        vault: vault,
        newTickLower: -300,
        newTickUpper: 600,
        decreaseAmount0Min: 0,
        decreaseAmount1Min: 0,
        amount0Min: 0,
        amount1Min: 0,
        automatorFee: 100,
        abiEncodedUserOrder: abiEncodedOrder,
        orderSignature: orderSignature,
      }),
    ).to.be.revertedWithCustomError(automator, "AccessControlUnauthorizedAccount");
  });
  it("shouldn't execute if in correct orderSignature", async () => {
    const orderSignature = await bob.signTypedData(domain, mockOrder.types, mockOrder.message);
    await expect(
      automator.connect(operator).executeRebalance({
        vault: vault,
        newTickLower: -300,
        newTickUpper: 600,
        decreaseAmount0Min: 0,
        decreaseAmount1Min: 0,
        amount0Min: 0,
        amount1Min: 0,
        automatorFee: 100,
        abiEncodedUserOrder: abiEncodedOrder,
        orderSignature: orderSignature,
      }),
    ).to.be.revertedWithCustomError(automator, "InvalidSignature");
  });
});
