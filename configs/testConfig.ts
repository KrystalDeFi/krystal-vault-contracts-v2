import { BaseTestConfig } from "./config_base";
import { ITestConfig } from "./interfaces";

const TestConfig: Record<string, ITestConfig> = {
  ...BaseTestConfig,
};

TestConfig.hardhat = {
  ...TestConfig["base_mainnet"],
};

export { TestConfig };
