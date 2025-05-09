pragma solidity ^0.8.0;

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import "./Config.sol";

import "forge-std/console.sol";     //forge-test-only
import { Test } from "forge-std/Test.sol";      //forge-test-only
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

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

    // this config is for the WETH/VIRTUAL pool on ETH mainnet https://etherscan.io/address/0x95a45a87dd4d3a1803039072f37e075f37b23d75#readContract
    uint24 public fee = 10000;
    int24 public tickLower = -71_000;
    int24 public tickUpper = -69_000;

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

    function callAllocate(address vaultAddress, uint256 principalTokenAmount, address tokenETHAddress, address tokenAnotherAddress, address configManagerAddress) public {
        
        console.log("this player address: %s", address(this));
        console.log("tokenETHAddress:                   %s", tokenETHAddress);
        console.log("eth amount of the player:          %s", IERC20(tokenETHAddress).balanceOf(address(this)));

        console.log("tokenAnotherAddress:               %s", tokenAnotherAddress);
        console.log("tokenAnother amount of the player: %s", IERC20(tokenAnotherAddress).balanceOf(address(this)));

        console.log("principalTokenAmount:              %s", principalTokenAmount);

        console.log("in player.callAllocate:: vault.allocate BEFORE");
        
        // for (uint256 i = 0; i < vault.getInventory().length; i++) {
        //     console.log("   + vaultAssets[%s].assetType: %s", i, uint256(vault.getInventory()[i].assetType));
        //     console.log("   + vaultAssets[%s].amount: %s", i, vault.getInventory()[i].amount);
        // }
        IVault vault = IVault(payable(vaultAddress));
        // console.log("vaultAssets.length: %s", vault.getInventory().length);        
        // console.log("amount of first asset: %s", vault.getInventory()[0].amount);
        // console.log("token of first asset: %s", vault.getInventory()[0].token);
        
        
        

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
            token1: tokenAnotherAddress,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Min: 0,
            amount1Min: 0,
            swapData: ""
        });
            
        ICommon.Instruction memory instruction = ICommon.Instruction({
            instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
            params: abi.encode(params)
        });

        console.log("vaultAssets.length (before): %s", vaultAssets.length);
        console.log("I will do allocate now");
        console.log("lp strategy address: %s", address(lpStrategy));

        
        console.log("A0 vault.getTotalValue():       %s" , vault.getTotalValue());

        vault.allocate(assets, lpStrategy, 0, abi.encode(instruction));
        console.log("A1212121 vault.getTotalValue(): %s" , vault.getTotalValue());
        
        // debug
        // address pool = IUniswapV3Factory(INFPM(NFPM_ON_ETH_MAINNET).factory()).getPool(tokenETHAddress, tokenAnotherAddress, fee);
        // console.log("pool address: %s", pool);
        
        console.log("in player.callAllocate:: vault.allocate done");
        console.log("vaultAssets.length: %s", vault.getInventory().length);        
        for (uint256 i = 0; i < vault.getInventory().length; i++) {
            console.log("   + vaultAssets[%s].assetType: %s", i, uint256(vault.getInventory()[i].assetType));
            console.log("   + vaultAssets[%s].amount: %s", i, vault.getInventory()[i].amount);
            // console.log("   + vaultAssets[%s].token: %s", i, vault.getInventory()[i].token);
        }

    }

    function doSwap(address token0Address, address token1Address, uint256 token0Amount) public {
        address pool = IUniswapV3Factory(INFPM(NFPM_ON_ETH_MAINNET).factory()).getPool(token0Address, token1Address, fee);
        
        PoolOptimalSwapper swapper = new PoolOptimalSwapper();
        IERC20(token0Address).approve(address(swapper), token0Amount);
        swapper.poolSwap(pool, token0Amount, token1Address > token0Address, 0, "");
    }
}
