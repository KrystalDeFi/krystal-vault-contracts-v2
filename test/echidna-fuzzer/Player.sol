pragma solidity ^0.8.0;

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import "./Config.sol";

import "forge-std/console.sol";     //forge-test-only
import { Test } from "forge-std/Test.sol";      //forge-test-only
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";

contract Player {

    event LogAddress(string, address);

    constructor() payable {
    } 

    function callDeposit(address vault, uint256 amount, address token) public returns (uint256) {
        IERC20(token).approve(vault, amount);    
        return IVault(payable(vault)).deposit(amount, 0);        
    }

    function callWithdraw(address vault, uint256 shares, uint256 minAmount) public {
        IVault(payable(vault)).withdraw(shares, false, minAmount);
    }

    function callCreateVault(address vaultFactory, ICommon.VaultCreateParams memory params) public returns (address) {
        return IVaultFactory(vaultFactory).createVault(params);
    }    

    function callAllocate(address vaultAddress, uint256 principalTokenAmount, address tokenETHAddress, address tokenUSDAddress, address configManagerAddress) public {
        
        console.log("this player address: %s", address(this));
        console.log("tokenETHAddress: %s", tokenETHAddress);
        console.log("tokenUSDAddress: %s", tokenUSDAddress);
        
        IVault vault = IVault(payable(vaultAddress));
        
        console.log("eth amount of the player: %s", IERC20(tokenETHAddress).balanceOf(address(this)));

        AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
        assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), tokenETHAddress, 0, principalTokenAmount);

        PoolOptimalSwapper swapper = new PoolOptimalSwapper();

        LpValidator validator = new LpValidator(configManagerAddress);
        LpFeeTaker feeTaker = new LpFeeTaker();

        AssetLib.Asset[] memory vaultAssets = vault.getInventory();

        LpStrategy lpStrategy = new LpStrategy(address(swapper), address(validator), address(feeTaker));

        ConfigManager configManager = ConfigManager(configManagerAddress);
        address[] memory strategies = new address[](1);
        strategies[0] = address(lpStrategy);
        configManager.whitelistStrategy(strategies, true);

        emit LogAddress("strategies[0]", strategies[0]);

        ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
            rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
            tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
        });

        initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });
        initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 ether });

        configManager.setStrategyConfig(address(validator), tokenETHAddress, abi.encode(initialConfig));


        ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
            nfpm: INFPM(NFPM_ON_ETH_MAINNET),
            token0: tokenETHAddress,
            token1: tokenUSDAddress,
            fee: 500,
            tickLower: 200_000,
            tickUpper: 202_000,
            amount0Min: 0,
            amount1Min: 0,
            swapData: ""
        });
            
        ICommon.Instruction memory instruction = ICommon.Instruction({
            instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
            params: abi.encode(params)
        });

        console.log("I will do allocate now");
        console.log("vaultAssets.length: %s", vaultAssets.length);
        console.log("lp strategy address: %s", address(lpStrategy));

        

        vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
        console.log("vault.allocate done");
        console.log("vaultAssets.length: %s", vaultAssets.length);

        assert(vaultAssets.length < 2);
    }
}
