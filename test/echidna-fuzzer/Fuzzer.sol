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
    LpStrategy public lpStrategy;
    
    IHevm hevm = IHevm(HEVM_ADDRESS);

    constructor() payable {
        owner = new Player();                
        player1 = new Player();        
        player2 = new Player();
        
        hevm.roll(BLOCK_NUMBER);
        hevm.warp(BLOCK_TIMESTAMP);

        hevm.startPrank(BANK_ADDRESS);
                
        IERC20(TOKEN_PRINCIPAL).transfer(address(owner), 2 ether);   // decimal of TOKEN_PRINCIPAL is 18
        IERC20(TOKEN_PRINCIPAL).transfer(address(player1), 2 ether);   // decimal of TOKEN_PRINCIPAL is 18        
        IERC20(TOKEN_PRINCIPAL).transfer(address(player2), 2 ether);   // decimal of TOKEN_PRINCIPAL is 18

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

    function assertTOKEN_PRINCIPALBalancePlayer1() public {    
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(player1));
        assert(wethBalance <= 2.0001 ether);
    }

    function assertTOKEN_PRINCIPALBalanceOwner() public {    
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        assert(wethBalance <= 2.0001 ether);
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

    function player1_doSwap(bool token0AddressIsTOKEN_PRINCIPAL, uint256 token0Amount) public {        
        player1.doSwap(token0AddressIsTOKEN_PRINCIPAL ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTOKEN_PRINCIPAL ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount);
    }

    function player2_doDepositPrincipalToken(uint256 amount) public {
        player2.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    }

    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }
    function player2_doSwap(bool token0AddressIsTOKEN_PRINCIPAL, uint256 token0Amount) public {        
        player2.doSwap(token0AddressIsTOKEN_PRINCIPAL ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTOKEN_PRINCIPAL ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount);
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
    

}

/*

* harvesting functions
* do the swap -> increate the liquidity

*/
