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


contract VaultFuzzer is TestCommon {
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

        setErc20Balance(TOKEN_PRINCIPAL, address(owner), 2 ether);
        setErc20Balance(TOKEN_PRINCIPAL, address(player1), 2 ether);
        setErc20Balance(TOKEN_PRINCIPAL, address(player2), 2 ether);
        setErc20Balance(TOKEN_PRINCIPAL, address(bighandplayer), 1_000 ether);
        // setErc20Balance(TOKEN_ANOTHER, address(owner), 3000 * 10 ** 6);
        // setErc20Balance(TOKEN_ANOTHER, address(player1), 3000 * 10 ** 6);
        // setErc20Balance(TOKEN_ANOTHER, address(player2), 3000 * 10 ** 6);        

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

        // Initialize the LpStrategy
        PoolOptimalSwapper swapper = new PoolOptimalSwapper();
        LpValidator validator = new LpValidator(configManagerAddress);
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

        console.log("Finished setup!");

    }

    function owner_doDepositPrincipalToken(uint256 amount) public {
        owner.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    }

    function owner_doWithdraw(uint256 shares) public {
        owner.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doDepositPrincipalToken(uint256 amount) public {
        player1.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    }

    function player1_doWithdraw(uint256 shares) public {
        player1.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount) public {        
        player1.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount);
    }

    function player2_doDepositPrincipalToken(uint256 amount) public {
        player2.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    }

    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }
    function player2_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount) public {        
        player2.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount);
    }

    function bighandplayer_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount) public {        
        bighandplayer.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount);
    }

    function owner_doAllocate(uint256 principalTokenAmount) public {
        require(principalTokenAmount > 0.001 ether);
        
        require( IVault(payable(vaultAddress)).getTotalValue() > 0.011 ether);
                
        owner.callAllocate(vaultAddress, principalTokenAmount, TOKEN_PRINCIPAL, TOKEN_ANOTHER, address(lpStrategy));        
        AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();              
        assert(vaultAssets.length >= 2);
    }

    function deposit_and_withdraw_only(uint256 amount) public {

        uint256 GAIN_MARGIN = 0.002 ether;

        uint256 ownerPTokenBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        uint256 sharesDelta = owner.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
        owner.callWithdraw(vaultAddress, sharesDelta, 0);

        // it is expected than the owner cant earn more than the initial amount after the deposit and withdraw
        assert( IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner)) <= (ownerPTokenBefore + GAIN_MARGIN) );

        uint256 player1PTokenBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        uint256 player1SharesDelta = player1.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
        player1.callWithdraw(vaultAddress, player1SharesDelta, 0);
        // emitLogUint256("player1PTokenBefore: %s", player1PTokenBefore);
        // emitLogUint256("player1PTokenAfter:  %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1)));
        assert (false);

        // it is expected than the player1 cant earn more than the initial amount after the deposit and withdraw
        assert( IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1)) <= (player1PTokenBefore + GAIN_MARGIN) );
    }

    function ownerCanWithdrawAll() public {
        require(IERC20(vaultAddress).balanceOf(address(owner)) > 10 * 10_000, "Owner has (almost) no shares");
        uint256 pTokenOwnerBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        try owner.callWithdraw(vaultAddress, IERC20(vaultAddress).balanceOf(address(owner)), 0) {} catch {
            console.log("There is an error when owner tries to withdraw all shares");
        }
        uint256 pTokenOwnerAfter = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        assert(pTokenOwnerAfter > pTokenOwnerBefore);
    }
    
    // function test_scenario2() public {
    //     console.log("====== test_scenario2 ====== ");
    //     bighandplayer_doSwap(true,710606880296704306061);
        
    //     bighandplayer_doSwap(false,10342869919687000738);
        
    //     owner_doDepositPrincipalToken(15769645103185095);
        
    //     owner_doAllocate(10139439508981706);
        
    //     bighandplayer_doSwap(false,193656859050591733150862);
        
    //     console.log("pToken balance of the owner: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner)));
    //     console.log("owner is doing the withdrawAll");
    //     ownerCanWithdrawAll();
    //     console.log("pToken balance of the owner: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner)));
    // }
    
    // function test_DepositAndWithdrawOnly() public {
    //     console.log("====== testDepositAndWithdrawOnly ====== ");
    //     bighandplayer_doSwap(true,585664197765691276451);
    //     owner_doDepositPrincipalToken(63787088001659878);
    //     owner_doAllocate(55706491220017704);
    //     bighandplayer_doSwap(false,85138858533936051110675);
    //     deposit_and_withdraw_only(6000000000000000);
    // }

    function partial_withdrawals(uint256 depositAmount, uint256 withdrawPercentage) public {
        require(depositAmount > 0 && withdrawPercentage > 0 && withdrawPercentage <= 100);
        uint256 initialBalance = IERC20(WETH).balanceOf(address(player1));
        console.log("p1 initialBalance: %s", initialBalance);

        uint256 shares = player1.callDeposit(vaultAddress, depositAmount, WETH);
        uint256 partialShares = (shares * withdrawPercentage) / 100;
        console.log("p1 shares: %s", shares);
        console.log("p1 partialShares: %s", partialShares);
        player1.callWithdraw(vaultAddress, partialShares, 0);        
        console.log("IERC20(WETH).balanceOf(address(player1)): %s", IERC20(WETH).balanceOf(address(player1)));
        player1.callWithdraw(vaultAddress, partialShares, 0);        
        console.log("IERC20(WETH).balanceOf(address(player1)): %s", IERC20(WETH).balanceOf(address(player1)));
        player1.callWithdraw(vaultAddress, partialShares, 0);        
        console.log("IERC20(WETH).balanceOf(address(player1)): %s", IERC20(WETH).balanceOf(address(player1)));
        assert(IERC20(WETH).balanceOf(address(player1)) <= initialBalance);
    }

    // function test_partial_withdrawals() public {
    //     console.log("====== test_partial_withdrawals ====== ");
    //     bighandplayer_doSwap(true,422183516766931138843);
    //     owner_doDepositPrincipalToken(35060558879820882);
    //     owner_doAllocate(32430576347458576);
    //     bighandplayer_doSwap(false,58692483655885087211515);
    //     partial_withdrawals(0.4 ether,1);
    // }
}


// Call sequence, shrinking 527/5000:
//     VaultFuzzerWithSwap.bighandplayer_doSwap(true,422183516766931138843)
//     VaultFuzzerWithSwap.owner_doDepositPrincipalToken(35060558879820882)
//     VaultFuzzerWithSwap.owner_doAllocate(32430576347458576)
//     VaultFuzzerWithSwap.bighandplayer_doSwap(false,58692483655885087211515)
//     VaultFuzzerWithSwap.partial_withdrawals(4,1)
