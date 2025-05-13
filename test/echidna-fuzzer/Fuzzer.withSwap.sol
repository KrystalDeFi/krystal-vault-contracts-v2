pragma solidity ^0.8.0;

import "./Player.sol";
import "./IHevm.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";

import "./Config.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";

address constant TOKEN_PRINCIPAL = WETH;
address constant TOKEN_ANOTHER = VIRTUAL;
uint256 constant BLOCK_NUMBER = 22365182;
uint256 constant BLOCK_TIMESTAMP = 1745814599;

contract VaultFuzzerWithSwap {
    
    event LogUint256(string, uint256);
    event LogAddress(string, address);
    event LogString(string);    

    Player public owner;
    Player public player1;
    Player public player2;
    Player public bighandplayer;
    
    VaultFactory public vaultFactory;
    address public vaultAddress;
    address public configManagerAddress;
    LpStrategy public lpStrategy;
    
    IHevm hevm = IHevm(HEVM_ADDRESS);

    constructor() payable {
        owner = new Player();                
        player1 = new Player();        
        player2 = new Player();
        bighandplayer = new Player();
        hevm.roll(BLOCK_NUMBER);
        hevm.warp(BLOCK_TIMESTAMP);

        hevm.startPrank(BANK_ADDRESS);
                
        IERC20(TOKEN_PRINCIPAL).transfer(address(owner), 2 ether);   // decimal of TOKEN_PRINCIPAL is 18
        IERC20(TOKEN_PRINCIPAL).transfer(address(player1), 2 ether);   // decimal of TOKEN_PRINCIPAL is 18        
        IERC20(TOKEN_PRINCIPAL).transfer(address(player2), 2 ether);   // decimal of TOKEN_PRINCIPAL is 18
        IERC20(TOKEN_PRINCIPAL).transfer(address(bighandplayer), 1_000 ether);

        hevm.stopPrank();

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

    }

    function assertPrincipleTokenBalanceOwnerWithUnbelievableAmount() public view {
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        assert(wethBalance <= 3 ether);
    }

    function assertPrincipleTokenBalancePlayer1WithUnbelievableAmount() public view {    
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        assert(wethBalance <= 3 ether);
    }

    function assertPrincipleTokenBalancePlayer2WithUnbelievableAmount() public view {
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2));
        assert(wethBalance <= 3 ether);
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
        require( principalTokenAmount > 0.01 ether);
        require( IVault(payable(vaultAddress)).getTotalValue() > 0.011 ether);
                
        owner.callAllocate(vaultAddress, principalTokenAmount, TOKEN_PRINCIPAL, TOKEN_ANOTHER, configManagerAddress, address(lpStrategy));        
        AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();      
        emit LogUint256("vaultAssets.length", vaultAssets.length);
        assert(vaultAssets.length >= 2);
    }

    function deposit_and_withdraw_only(uint256 amount) public {
        uint256 ownerTOKEN_PRINCIPALBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));        
        
        uint256 sharesDelta = owner.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
        owner.callWithdraw(vaultAddress, sharesDelta, 0);

        // it is expected than the owner cant earn more than the initial amount after the deposit and withdraw
        assert( IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner)) <= ownerTOKEN_PRINCIPALBefore );

        uint256 player1TOKEN_PRINCIPALBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        uint256 player1SharesDelta = player1.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
        player1.callWithdraw(vaultAddress, player1SharesDelta, 0);

        // it is expected than the player1 cant earn more than the initial amount after the deposit and withdraw
        assert( IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1)) <= player1TOKEN_PRINCIPALBefore );
    }

    function deposit_withdraw_empty_vault() public {
        require( IVault(payable(vaultAddress)).getTotalValue() == 0 );     // in this case, no one has never deposited into the vault

        uint256 ownerTOKEN_PRINCIPALBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        uint256 ownerSharesDelta = owner.callDeposit(vaultAddress, 1 ether, TOKEN_PRINCIPAL);
        owner.callWithdraw(vaultAddress, ownerSharesDelta, 0);
        
        assert( IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner)) == ownerTOKEN_PRINCIPALBefore );    // it is expected that the owner has not earned or lost any amount
    }

    // this function is for debugging purpose
    // function assets_length() public {
    //     AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();
    //     assert(vaultAssets.length == 1);
    // }

    function multiple_deposits_withdrawals(uint256 amount1, uint256 amount2) public {
        require(amount1 > 0 && amount2 > 0);
        uint256 initialBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        
        uint256 shares1 = player1.callDeposit(vaultAddress, amount1, TOKEN_PRINCIPAL);
        uint256 shares2 = player1.callDeposit(vaultAddress, amount2, TOKEN_PRINCIPAL);
        
        player1.callWithdraw(vaultAddress, shares1 + shares2, 0);
        
        assert(IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1)) <= initialBalance);
    }

    function partial_withdrawals(uint256 depositAmount, uint256 withdrawPercentage) public {
        require(depositAmount > 0 && withdrawPercentage > 0 && withdrawPercentage <= 100);
        uint256 initialBalance = IERC20(WETH).balanceOf(address(player1));
        
        uint256 shares = player1.callDeposit(vaultAddress, depositAmount, WETH);
        uint256 partialShares = (shares * withdrawPercentage) / 100;
        
        player1.callWithdraw(vaultAddress, partialShares, 0);
        assert(IERC20(WETH).balanceOf(address(player1)) <= initialBalance);
    }

    function ownerCanWithdrawAll() public {
        require(IERC20(vaultAddress).balanceOf(address(owner)) > 10 * 10_000, "Owner has (almost) no shares");
        uint256 pTokenOwnerBefore = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        try owner.callWithdraw(vaultAddress, IERC20(vaultAddress).balanceOf(address(owner)), 0) {} catch {
            emit LogString("There is an error when owner tries to withdraw all shares");
        }
        uint256 pTokenOwnerAfter = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        assert(pTokenOwnerAfter > pTokenOwnerBefore);
    }

    function player1CanWithdrawAll() public {
        require(IERC20(vaultAddress).balanceOf(address(player1)) > 10 * 10_000, "Player1 has (almost)no shares");
        uint256 pTokenPlayer1Before = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        try player1.callWithdraw(vaultAddress, IERC20(vaultAddress).balanceOf(address(player1)), 0) {} catch {
            emit LogString("There is an error when player1 tries to withdraw all shares");
        }
        uint256 pTokenPlayer1After = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        assert(pTokenPlayer1After > pTokenPlayer1Before);
    }

    function player2CanWithdrawAll() public {
        require(IERC20(vaultAddress).balanceOf(address(player2)) > 10 * 10_000, "Player2 has (almost) no shares");
        uint256 pTokenPlayer2Before = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2));
        try player2.callWithdraw(vaultAddress, IERC20(vaultAddress).balanceOf(address(player2)), 0) {} catch {
            emit LogString("There is an error when player2 tries to withdraw all shares");
        }
        uint256 pTokenPlayer2After = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2));
        assert(pTokenPlayer2After > pTokenPlayer2Before);
    }

}
    // function test_scenario() public {

    //     // player2_doDepositPrincipalToken(1 ether);
    //     // console.log("player2 shares: %s", player2Shares);
    
    //     // console.log("player2 balance: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2)));

    //     // console.log("vault total value (B): %s", IVault(payable(vaultAddress)).getTotalValue());
    //     owner_doAllocate(1 ether);
    //     // console.log("vault total value (A): %s", IVault(payable(vaultAddress)).getTotalValue());                
    //     // console.log("player2 shares:    %s", player2Shares);

    //     bighandplayer_doSwap(true, 500 ether);
    //     // bighandplayer.doSwap(TOKEN_PRINCIPAL, TOKEN_ANOTHER, 20 ether);

    //     player2_doWithdraw(IERC20(vaultAddress).balanceOf(address(player2)));

    //     emit LogUint256("player2 balance after withdraw: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2)));
    //     // uint256 player2Balance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2));
    //     // assert( player2Balance <= 2 ether);
    //     // console.log("player2 balance: %s", IERC20(TOKEN_PRINCIPAL).balanceOf(address(player2)));

    // }
    
/*

* harvesting functions
* do the swap -> increate the liquidity

*/


/*
Call sequence:                                                                                                                      
1. VaultFuzzerWithSwap.player1_doDepositPrincipalToken(44)                                                                          
2. VaultFuzzerWithSwap.deposit_and_withdraw_only(101351549933237796)                                                               
3. VaultFuzzerWithSwap.player1_doWithdraw(438355)                                                                                  
4. VaultFuzzerWithSwap.assertPrincipleTokenBalancePlayer1()        
*/
