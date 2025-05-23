// This is a test file to develop the VaultFuzzer contract

pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import "./Player.sol";
import "./Config.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";
import "../../contracts/interfaces/ICommon.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { LpFeeTaker } from "../../contracts/strategies/lpUniV3/LpFeeTaker.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { TestCommon } from "../TestCommon.t.sol";

address constant TOKEN_PRINCIPAL = WETH;
address constant TOKEN_ANOTHER = VIRTUAL;
uint256 constant BLOCK_NUMBER = 22365182;
uint256 constant BLOCK_TIMESTAMP = 1745814599;
uint256 constant PLAYER_INITIAL_PTOKEN_BALANCE = 2 ether;
int24 constant TICK_LOWER_CONFIG = -71_000;
int24 constant TICK_UPPER_CONFIG = -69_000;

contract FoundryTestSoloPlayer is TestCommon {
    Player public owner;
    Player public player1;
    Player public player2;
    Player public bighandplayer;
    VaultFactory public vaultFactory;
    address public vaultAddress;
    
    address public configManagerAddress;
    
    LpStrategy public lpStrategy;

    function setUp() public {
        owner = new Player();                
        player1 = new Player();        
        player2 = new Player();
        bighandplayer = new Player();
        
        uint256 fork = vm.createFork(vm.envString("ECHIDNA_RPC_URL"), BLOCK_NUMBER);
        vm.selectFork(fork);

        console.log("block.timestamp: %s", block.timestamp);

        setErc20Balance(TOKEN_PRINCIPAL, address(owner), PLAYER_INITIAL_PTOKEN_BALANCE);
        setErc20Balance(TOKEN_PRINCIPAL, address(player1), PLAYER_INITIAL_PTOKEN_BALANCE);
        setErc20Balance(TOKEN_PRINCIPAL, address(player2), PLAYER_INITIAL_PTOKEN_BALANCE);
        setErc20Balance(TOKEN_PRINCIPAL, address(bighandplayer), 1_000 ether);

        address[] memory whitelistAutomator = new address[](1);
        whitelistAutomator[0] = address(player1);

        address[] memory typedTokens = new address[](2);
        typedTokens[0] = TOKEN_PRINCIPAL;
        typedTokens[1] = TOKEN_ANOTHER;

        uint256[] memory typedTokenTypes = new uint256[](2);
        typedTokenTypes[0] = uint256(1);
        typedTokenTypes[1] = uint256(1);

        ConfigManager configManager = new ConfigManager();
        configManager.initialize(
            address(owner),
            new address[](0),
            new address[](0),
            whitelistAutomator,
            new address[](0),
            typedTokens,
            typedTokenTypes,
            0,
            0,
            0,
            address(0),
            new address[](0),
            new address[](0),
            new bytes[](0)
        );        
        configManagerAddress = address(configManager);        

        address[] memory whitelistNfpms = new address[](1);
        whitelistNfpms[0] = address(NFPM_ON_ETH_MAINNET);
        // Initialize the LpStrategy
        PoolOptimalSwapper swapper = new PoolOptimalSwapper();
        LpValidator validator = new LpValidator();
        validator.initialize(address(this), configManagerAddress, whitelistNfpms);
        LpFeeTaker feeTaker = new LpFeeTaker();
        lpStrategy = new LpStrategy(address(swapper), address(validator), address(feeTaker));        
        
        
        // Whitelist the LpStrategy for the configManager
        address[] memory strategies = new address[](1);
        strategies[0] = address(lpStrategy);
        owner.callWhitelistStrategy(configManagerAddress, strategies, true);        

        // Set the initial config for the LpStrategy in the configManager
        ILpValidator.LpStrategyConfig memory initialConfig = ILpValidator.LpStrategyConfig({
            rangeConfigs: new ILpValidator.LpStrategyRangeConfig[](1),
            tvlConfigs: new ILpValidator.LpStrategyTvlConfig[](1)
        });
        initialConfig.rangeConfigs[0] = ILpValidator.LpStrategyRangeConfig({ tickWidthMin: 3, tickWidthTypedMin: 3 });
        initialConfig.tvlConfigs[0] = ILpValidator.LpStrategyTvlConfig({ principalTokenAmountMin: 0 ether });
        owner.callSetStrategyConfig(configManagerAddress, address(validator), TOKEN_PRINCIPAL, initialConfig);

        // Initialize the VaultFactory. The owner of the VaultFactory is this contract.
        Vault vaultImplementation = new Vault();
        vaultFactory = new VaultFactory();
        vaultFactory.initialize(address(owner), TOKEN_PRINCIPAL, configManagerAddress, address(vaultImplementation));    
        ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
            name: "Test Public Vault",
            symbol: "TV",
            principalTokenAmount: 0,
            config: ICommon.VaultConfig({
                allowDeposit: true,
                rangeStrategyType: 0,
                tvlStrategyType: 0,
                principalToken: TOKEN_PRINCIPAL,
                supportedAddresses: new address[](0)
            })
        });

        // Call createVault through the owner contract
        vaultAddress = owner.callCreateVault(address(vaultFactory), params);

        owner.callDeposit(vaultAddress, 1 ether, TOKEN_PRINCIPAL);
        player1.callDeposit(vaultAddress, 1 ether, TOKEN_PRINCIPAL);
        owner.callAllocate(vaultAddress, 1.2 ether, TOKEN_PRINCIPAL, TOKEN_ANOTHER, address(lpStrategy), TICK_LOWER_CONFIG, TICK_UPPER_CONFIG, 10_000);
        bighandplayer.doSwap(TOKEN_PRINCIPAL, TOKEN_ANOTHER, 3 ether, 10_000);

        console.log("Finished setup!");

    }

    function assertPrincipleTokenBalancePlayer2() public view {
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        assert(wethBalance <= PLAYER_INITIAL_PTOKEN_BALANCE);
    }
    
    function owner_doWithdraw(uint256 shares) public {
        owner.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doWithdraw(uint256 shares) public {
        player1.callWithdraw(vaultAddress, shares, 0);
    }
    function player2_doDepositPrincipalToken(uint256 amount) public {
        player2.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    }
    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }
    function player2_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount) public {        
        player2.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount, 10_000);
    }

    function test_printTheState() public {
        console.log("vaultAddress: %s", vaultAddress);
        console.log("owner balance: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner)));
        console.log("player1 balance: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1)));
        console.log("player2 balance: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2)));
        console.log("bighandplayer balance: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(bighandplayer)));
        console.log("player1 shares: %s", IERC20(vaultAddress).balanceOf(address(player1)));
        console.log("player2 shares: %s", IERC20(vaultAddress).balanceOf(address(player2)));
        console.log("bighandplayer shares: %s", IERC20(vaultAddress).balanceOf(address(bighandplayer)));
        
        AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();              
        for (uint256 i = 0; i < vaultAssets.length; i++) {
            console.log("vaultAssets[%s] token: %s", i, vaultAssets[i].token);
            console.log("vaultAssets[%s] tokenId: %s", i, vaultAssets[i].tokenId);
            console.log("vaultAssets[%s] amount: %s", i, vaultAssets[i].amount);
        }

        
        
    }

}


