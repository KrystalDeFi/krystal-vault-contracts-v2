// This is a test file to develop the VaultFuzzer contract

pragma solidity ^0.8.0;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import "./Player.sol";
import "./Config.sol";
import "./IHevm.sol";
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

contract VaultFuzzer is TestCommon {
    Player public owner;
    Player public player1;
    Player public player2;
    Player public bighandplayer;
    VaultFactory public vaultFactory;
    address public vaultAddress;
    
    address public configManagerAddress;


    function setUp() public {
        owner = new Player();                
        player1 = new Player();        
        player2 = new Player();
        bighandplayer = new Player();
        

        uint256 fork = vm.createFork(vm.envString("ECHIDNA_RPC_URL"), 22443326);
        vm.selectFork(fork);

        console.log("block.timestamp: %s", block.timestamp);

        setErc20Balance(WETH, address(owner), 2 ether);
        setErc20Balance(WETH, address(player1), 2 ether);
        setErc20Balance(WETH, address(player2), 2 ether);
        setErc20Balance(WETH, address(bighandplayer), 200 ether);
        // setErc20Balance(VIRTUAL, address(owner), 3000 * 10 ** 6);
        // setErc20Balance(VIRTUAL, address(player1), 3000 * 10 ** 6);
        // setErc20Balance(VIRTUAL, address(player2), 3000 * 10 ** 6);        

        address[] memory whitelistAutomator = new address[](1);
        whitelistAutomator[0] = address(player1);

        address[] memory typedTokens = new address[](2);
        typedTokens[0] = WETH;
        typedTokens[1] = VIRTUAL;

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

        Vault vaultImplementation = new Vault();
        
        vaultFactory = new VaultFactory();
        vaultFactory.initialize(address(owner), WETH, configManagerAddress, address(vaultImplementation));
    
        ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
            name: "Test Public Vault",
            symbol: "TV",
            principalTokenAmount: 0,
            config: ICommon.VaultConfig({
                allowDeposit: true,
                rangeStrategyType: 0,
                tvlStrategyType: 0,
                principalToken: WETH,
                supportedAddresses: new address[](0)
            })
        });

        // Call createVault through the owner contract
        vaultAddress = owner.callCreateVault(address(vaultFactory), params);

        console.log("Finished setup!");

    }

    // function assertWETHBalancePlayer1() public {        
    //     assert(IERC20(WETH).balanceOf(address(player1)) >= 2 ether);
    // }


    function owner_doDepositPrincipalToken(uint256 amount) public returns (uint256) {
        return owner.callDeposit(vaultAddress, amount, WETH);
    }

    function owner_doWithdraw(uint256 shares) public {
        owner.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doDepositPrincipalToken(uint256 amount) public returns (uint256) {
        return player1.callDeposit(vaultAddress, amount, WETH);
    }

    function player1_doWithdraw(uint256 shares) public {
        player1.callWithdraw(vaultAddress, shares, 0);
    }

    function player2_doDepositPrincipalToken(uint256 amount) public returns (uint256) {
        return player2.callDeposit(vaultAddress, amount, WETH);
    }

    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }


    function deposit_and_withdraw() public {
        uint256 amount = 1 ether;
        

        console.log("IERC20(WETH).balanceOf(address(owner)) x: %s", IERC20(WETH).balanceOf(address(owner)));

        uint256 ownerShares = owner.callDeposit(vaultAddress, amount, WETH);
        console.log("owner deposited %s", amount);
        console.log("IERC20(WETH).balanceOf(address(owner)) x: %s", IERC20(WETH).balanceOf(address(owner)));
        

        uint256 player1Shares = player1.callDeposit(vaultAddress, amount, WETH);
        console.log("p1 deposited %s", amount);
        console.log("IERC20(WETH).balanceOf(address(player1)) x: %s", IERC20(WETH).balanceOf(address(player1)));


        player1.callWithdraw(vaultAddress, player1Shares, 0);
        owner.callWithdraw(vaultAddress, ownerShares, 0);
        
        console.log("IERC20(WETH).balanceOf(address(owner))  x: %s", IERC20(WETH).balanceOf(address(owner)));
        console.log("IERC20(WETH).balanceOf(address(player1)) x: %s", IERC20(WETH).balanceOf(address(player1)));

        // assert( tokenETH.balanceOf(address(owner)) == ownerTokenEthBefore );
    }

    function always_true(uint256 a) public pure {
        assert( true );
    }

    function owner_doAllocate(uint256 principalTokenAmount) public {
        require( principalTokenAmount > 0.01 ether);
        require( IVault(payable(vaultAddress)).getTotalValue() > 0.011 ether);
                
        owner.callAllocate(vaultAddress, principalTokenAmount, WETH, VIRTUAL, configManagerAddress);        
        AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();      
        // emit LogUint256("vaultAssets.length", vaultAssets.length);
        console.log("owner_doAllocate:: vaultAssets.length: %s", vaultAssets.length);
        assert(vaultAssets.length >= 2);

        for (uint256 i = 0; i < vaultAssets.length; i++) {
            console.log("owner_doAllocate:: vaultAssets[%s].assetType: %s", i, uint256(vaultAssets[i].assetType));
            console.log("owner_doAllocate:: vaultAssets[%s].amount: %s", i, vaultAssets[i].amount);
            console.log("owner_doAllocate:: vaultAssets[%s].token: %s", i, vaultAssets[i].token);
        }
    }    
    
    function test_scenario() public {

    
        uint256 player2Shares = player2_doDepositPrincipalToken(0.04 ether);
        console.log("player2 shares: %s", player2Shares);
    
        console.log("player2 balance: %s", IERC20(WETH).balanceOf(address(player2)));
        owner_doAllocate(0.02 ether);

                
        console.log("player2 shares:    %s", player2Shares);

        player2_doWithdraw(player2Shares);
        console.log("player2 balance: %s", IERC20(WETH).balanceOf(address(player2)));
        
    }

}
