import { ethers } from "hardhat";
import { expect } from "chai";
import { OptimalSwapLibTest } from "../typechain-types";

describe("OptimalSwap", () => {
  it("should calculate zeroForOne correctly with small numbers", async () => {
    const optimalSwap = await ethers.deployContract("OptimalSwapLibTest");
    await optimalSwap.waitForDeployment();
    {
      const isZeroForOne = await optimalSwap.isZeroForOneInRange(
        "808401318",
        "0",
        "3951727649479010892136946",
        "3851966005701440317093773",
        "4049450403053124526823087",
      );
      expect(isZeroForOne).to.be.true;
    }

    {
      const isZeroForOne = await optimalSwap.isZeroForOneInRange(
        "0",
        "808401318",
        "3951727649479010892136946",
        "3851966005701440317093773",
        "4049450403053124526823087",
      );
      expect(isZeroForOne).to.be.false;
    }
  });
});
