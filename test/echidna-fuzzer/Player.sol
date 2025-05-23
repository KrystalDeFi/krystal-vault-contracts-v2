pragma solidity ^0.8.0;

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { IConfigManager } from "../../contracts/interfaces/core/IConfigManager.sol";
import "./Config.sol";

import "forge-std/console.sol";     //forge-test-only
import { Test } from "forge-std/Test.sol";      //forge-test-only
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IStrategy } from "../../contracts/interfaces/strategies/IStrategy.sol";

import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";


contract Player {

    // this config is for the WETH/VIRTUAL pool on ETH mainnet https://etherscan.io/address/0x95a45a87dd4d3a1803039072f37e075f37b23d75#readContract
    // uint24 public fee = 10000;
    
    constructor() payable {
    }

    function callWhitelistStrategy(address configManagerAddress, address[] memory strategies, bool isWhitelisted) public {
        IConfigManager(configManagerAddress).whitelistStrategy(strategies, isWhitelisted);
    }

    function callSetStrategyConfig(address configManagerAddress, address validator, address principalTokenAddress, ILpValidator.LpStrategyConfig memory config) public {
        IConfigManager(configManagerAddress).setStrategyConfig(validator, principalTokenAddress, abi.encode(config));
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

    function callAllocate(address vaultAddress, uint256 principalTokenAmount, address tokenPrincipalAddress, address tokenAnotherAddress, address strategyAddress, int24 tickLower, int24 tickUpper, uint24 fee) public {
        IVault vault = IVault(payable(vaultAddress));        
        
        AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
        assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), tokenPrincipalAddress, 0, principalTokenAmount);        

        address token0;
        address token1;
        if (tokenPrincipalAddress < tokenAnotherAddress) {
            token0 = tokenPrincipalAddress;
            token1 = tokenAnotherAddress;
        } else {
            token0 = tokenAnotherAddress;
            token1 = tokenPrincipalAddress;
        }

        ILpStrategy.SwapAndMintPositionParams memory params = ILpStrategy.SwapAndMintPositionParams({
            nfpm: INFPM(NFPM_ON_ETH_MAINNET),
            token0: token0,
            token1: token1,
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

        
        vault.allocate(assets, IStrategy(strategyAddress), 0, abi.encode(instruction));

    }

    function doSwap(address token0Address, address token1Address, uint256 token0Amount, uint24 fee) public {
        address pool = IUniswapV3Factory(INFPM(NFPM_ON_ETH_MAINNET).factory()).getPool(token0Address, token1Address, fee);
        
        PoolOptimalSwapper swapper = new PoolOptimalSwapper();
        IERC20(token0Address).approve(address(swapper), token0Amount);
        swapper.poolSwap(pool, token0Amount, token1Address > token0Address, 0, "");
    }
}
