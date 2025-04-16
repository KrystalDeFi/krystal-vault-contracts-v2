pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";

import { TestCommon, USER, PLAYER_1, PLAYER_2, BIGHAND_PLAYER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";


contract Fuzzer is TestCommon {
    
  ConfigManager public configManager;
  LpStrategy public lpStrategy;
  VaultFactory public vaultFactory;
  Vault public vaultImplementation;  
  constructor() {
    console.log("in the constructor func");

    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    // vm.selectFork(fork);

    // ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
    //   rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
    //   tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
    // });

    // initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });

    // initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0.1 ether });
    
    
    // // Set up ConfigManager
    // address[] memory typedTokens = new address[](2);
    // typedTokens[0] = DAI;
    // typedTokens[1] = USDC;

    // uint256[] memory typedTokenTypes = new uint256[](2);
    // typedTokenTypes[0] = uint256(1);
    // typedTokenTypes[1] = uint256(1);

    // address[] memory whitelistAutomator = new address[](1);
    // whitelistAutomator[0] = USER;

    // configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);
    // console.log("configManager: ", address(configManager));
    // PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    // LpValidator validator = new LpValidator(address(configManager));
    // lpStrategy = new LpStrategy(address(swapper), address(validator));

    // vaultImplementation = new Vault();
    // console.log("vaultImplementation: ", address(vaultImplementation));

    // vm.startPrank(USER);
    // configManager.setStrategyConfig(address(validator), WETH, abi.encode(initialConfig));
    // console.log("setStrategyConfig");
    // vaultFactory = new VaultFactory(USER, WETH, address(configManager), address(vaultImplementation));
  }
  
  function get_config_owner() public returns (address) {
    return configManager.owner();
  }

  function getShares_never_reverts() public {
    assert(configManager.owner() == DAI);
    assert(true);
  }
  
  function aFunc_never_reverts() public {    
    assert(false);
  }

  function test_smt() public {
    console.log("Im in the test_smt func");
  }

}
