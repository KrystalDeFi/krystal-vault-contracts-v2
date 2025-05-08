pragma solidity ^0.8.0;

import "./Player.sol";
import "./IHevm.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";

import "./Config.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";

contract VaultFuzzer {
    
    event LogUint256(string, uint256);
    event LogAddress(string, address);
    event LogString(string);    

    Player public owner;
    Player public player1;
    Player public player2;
    
    VaultFactory public vaultFactory;
    address public vaultAddress;
    address public configManagerAddress;
    
    IHevm hevm = IHevm(HEVM_ADDRESS);

    constructor() payable {
        owner = new Player();                
        player1 = new Player();        
        player2 = new Player();
        
        hevm.roll(22365182);
        hevm.warp(1745814599);

        hevm.startPrank(BANK_ADDRESS);
        
        IERC20(USDC).transfer(address(owner), 10);   // decimal of USDC is 6
        IERC20(WETH).transfer(address(owner), 2 ether);   // decimal of WETH is 18

        IERC20(USDC).transfer(address(player1), 10);   // decimal of USDC is 6
        IERC20(WETH).transfer(address(player1), 2 ether);   // decimal of WETH is 18

        IERC20(USDC).transfer(address(player2), 10);   // decimal of USDC is 6
        IERC20(WETH).transfer(address(player2), 2 ether);   // decimal of WETH is 18

        hevm.stopPrank();


        
        address[] memory whitelistAutomator = new address[](1);
        whitelistAutomator[0] = address(player1);

        address[] memory typedTokens = new address[](2);
        typedTokens[0] = WETH;
        typedTokens[1] = USDC;

        uint256[] memory typedTokenTypes = new uint256[](2);
        typedTokenTypes[0] = uint256(1);
        typedTokenTypes[1] = uint256(1);

        configManagerAddress = address(new ConfigManager(address(owner), whitelistAutomator, typedTokens, typedTokenTypes));

        Vault vaultImplementation = new Vault();
        vaultFactory = new VaultFactory(address(owner), WETH, configManagerAddress, address(vaultImplementation));
    
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

    }

    function assertWETHBalancePlayer1() public {    
        uint256 wethBalance = IERC20(WETH).balanceOf(address(player1));
        assert(wethBalance <= 2.0001 ether);
    }

    function assertWETHBalanceOwner() public {    
        uint256 wethBalance = IERC20(WETH).balanceOf(address(owner));
        assert(wethBalance <= 2.0001 ether);
    }

    function owner_doDepositPrincipalToken(uint256 amount) public {
        owner.callDeposit(vaultAddress, amount, WETH);
    }

    function owner_doWithdraw(uint256 shares) public {
        owner.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doDepositPrincipalToken(uint256 amount) public {
        player1.callDeposit(vaultAddress, amount, WETH);
    }

    function player1_doWithdraw(uint256 shares) public {
        player1.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doSwap(bool token0AddressIsWETH, uint256 token0Amount) public {        
        player1.doSwap(token0AddressIsWETH ? WETH : USDC, token0AddressIsWETH ? USDC : WETH, 500, token0Amount);
    }

    function player2_doDepositPrincipalToken(uint256 amount) public {
        player2.callDeposit(vaultAddress, amount, WETH);
    }

    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }
    function player2_doSwap(bool token0AddressIsWETH, uint256 token0Amount) public {        
        player2.doSwap(token0AddressIsWETH ? WETH : USDC, token0AddressIsWETH ? USDC : WETH, 500, token0Amount);
    }

    function owner_doAllocate(uint256 principalTokenAmount) public {
        require( principalTokenAmount > 0.01 ether);
        require( IVault(payable(vaultAddress)).getTotalValue() > 0.011 ether);
                
        owner.callAllocate(vaultAddress, principalTokenAmount, WETH, USDC, configManagerAddress);        
        AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();      
        emit LogUint256("vaultAssets.length", vaultAssets.length);
        assert(vaultAssets.length >= 2);
    }    

    function deposit_and_withdraw_only(uint256 amount) public {
        uint256 ownerWETHBefore = IERC20(WETH).balanceOf(address(owner));        
        
        uint256 sharesDelta = owner.callDeposit(vaultAddress, amount, WETH);
        owner.callWithdraw(vaultAddress, sharesDelta, 0);

        // it is expected than the owner cant earn more than the initial amount after the deposit and withdraw
        assert( IERC20(WETH).balanceOf(address(owner)) <= ownerWETHBefore );

        uint256 player1WETHBefore = IERC20(WETH).balanceOf(address(player1));
        uint256 player1SharesDelta = player1.callDeposit(vaultAddress, amount, WETH);
        player1.callWithdraw(vaultAddress, player1SharesDelta, 0);

        // it is expected than the player1 cant earn more than the initial amount after the deposit and withdraw
        assert( IERC20(WETH).balanceOf(address(player1)) <= player1WETHBefore );
    }

    function deposit_withdraw_empty_vault() public {
        require( IVault(payable(vaultAddress)).getTotalValue() == 0 );     // in this case, no one has never deposited into the vault

        uint256 ownerWETHBefore = IERC20(WETH).balanceOf(address(owner));
        uint256 ownerSharesDelta = owner.callDeposit(vaultAddress, 1 ether, WETH);
        owner.callWithdraw(vaultAddress, ownerSharesDelta, 0);
        
        assert( IERC20(WETH).balanceOf(address(owner)) == ownerWETHBefore );    // it is expected that the owner has not earned or lost any amount
    }

    // this function is for debugging purpose
    // function assets_length() public {
    //     AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();
    //     assert(vaultAssets.length == 1);
    // }

    function multiple_deposits_withdrawals(uint256 amount1, uint256 amount2) public {
        require(amount1 > 0 && amount2 > 0);
        uint256 initialBalance = IERC20(WETH).balanceOf(address(player1));
        
        uint256 shares1 = player1.callDeposit(vaultAddress, amount1, WETH);
        uint256 shares2 = player1.callDeposit(vaultAddress, amount2, WETH);
        
        player1.callWithdraw(vaultAddress, shares1 + shares2, 0);
        
        assert(IERC20(WETH).balanceOf(address(player1)) <= initialBalance);
    }
    

}

/*

* harvesting functions
* do the swap -> increate the liquidity

*/
