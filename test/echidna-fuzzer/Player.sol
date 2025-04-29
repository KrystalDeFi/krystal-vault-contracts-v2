pragma solidity ^0.8.0;

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import "../../contracts/core/Vault.sol";
import "./MockERC20Token.sol";
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
import { IWETH9 } from "../../contracts/interfaces/IWETH9.sol";

contract Player {
    constructor() payable {
    } 

    function callDeposit(address vault, uint256 amount, MockERC20Token token) public returns (uint256) {
        token.approve(vault, amount);    
        return Vault(payable(vault)).deposit(amount, 0);        
    }

    function callWithdraw(address vault, uint256 shares, uint256 minAmount) public {
        Vault(payable(vault)).withdraw(shares, false, minAmount);
    }

    function callCreateVault(address vaultFactory, ICommon.VaultCreateParams memory params) public returns (address) {
        return IVaultFactory(vaultFactory).createVault(params);
    }

    function callDepositWETH(uint256 amount) public {
        IWETH9(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)).deposit{value: amount}();
    }

    function callAllocate(address vaultAddress, uint256 principalTokenAmount, address tokenETHAddress, address tokenUSDAddress, address configManagerAddress) public {
        
        console.log("this player address: %s", address(this));
        console.log("tokenETHAddress: %s", tokenETHAddress);
        console.log("tokenUSDAddress: %s", tokenUSDAddress);
        
        Vault vault = Vault(payable(vaultAddress));
        
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

        ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
            rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
            tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
        });

        initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });
        initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 ether });
        configManager.setStrategyConfig(address(validator), tokenETHAddress, abi.encode(initialConfig));

        ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
            nfpm: INFPM(NFPM),
            token0: tokenETHAddress,
            token1: tokenUSDAddress,
            fee: 500,
            tickLower: -287_220,
            tickUpper: -107_220,
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
