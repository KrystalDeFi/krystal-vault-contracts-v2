/*

    In this fuzzer, the owner initializes the vault and the player1 & player 2 deposits. The bighand player swapped with an amount.
    Later, the owner is trying to take almost all the balance of the vault.
*/

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
uint256 constant PLAYER_INITIAL_PTOKEN_BALANCE = 2 ether;
int24 constant TICK_LOWER_CONFIG = -71_000;
int24 constant TICK_UPPER_CONFIG = -69_000;
int24 constant TICK_SPACING_MULTIPLIER = 200;

contract VaultFuzzerSoloOwner {
    
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
                
        IERC20(TOKEN_PRINCIPAL).transfer(address(owner), PLAYER_INITIAL_PTOKEN_BALANCE);   // decimal of TOKEN_PRINCIPAL is 18
        IERC20(TOKEN_PRINCIPAL).transfer(address(player1), PLAYER_INITIAL_PTOKEN_BALANCE);   // decimal of TOKEN_PRINCIPAL is 18        
        IERC20(TOKEN_PRINCIPAL).transfer(address(player2), PLAYER_INITIAL_PTOKEN_BALANCE);   // decimal of TOKEN_PRINCIPAL is 18
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

        // Initialize the TOKEN_ANOTHER balance of the vault
        bighandplayer.doSwap(TOKEN_PRINCIPAL, TOKEN_ANOTHER, 50 ether, 10_000);

        owner.callDeposit(vaultAddress, 1 ether, TOKEN_PRINCIPAL);
        player1.callDeposit(vaultAddress, 1 ether, TOKEN_PRINCIPAL);
        player2.callDeposit(vaultAddress, 1 ether, TOKEN_PRINCIPAL);
        owner_doAllocateFixedTickRange(1.5 ether, TOKEN_PRINCIPAL, TOKEN_ANOTHER);
        // owner.callAllocate(vaultAddress, 1.5 ether, TOKEN_PRINCIPAL, TOKEN_ANOTHER, address(lpStrategy));
        
        // Generate some fee for the vault
        bighandplayer.doSwap(TOKEN_PRINCIPAL, TOKEN_ANOTHER, 1 ether, 10_000);

    }

    function assertPrincipleTokenBalanceOwner() public {
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        emit LogUint256("wethBalance of owner", wethBalance);
        assert(wethBalance <= PLAYER_INITIAL_PTOKEN_BALANCE);        
    }
    
    function owner_doWithdraw(uint256 shares) public {
        owner.callWithdraw(vaultAddress, shares, 0);
    }

    function owner_doWithdrawAll() public {
        owner.callWithdraw(vaultAddress, IERC20(vaultAddress).balanceOf(address(owner)), 0);
    }

    function player1_doWithdraw(uint256 shares) public {
        player1.callWithdraw(vaultAddress, shares, 0);
    }

    function owner_doDepositPrincipalToken(uint256 amount) public {
        owner.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    }

    function owner_doDepositAnotherToken(uint256 amount) public {
        owner.callDeposit(vaultAddress, amount, TOKEN_ANOTHER);
    }    

    function owner_doAllocate(uint256 amount, address token0, address token1, int24 tickLower, int24 tickMultiplier, uint24 fee) public {
        require(tickLower % TICK_SPACING_MULTIPLIER == 0, "Invalid tickLower");
        require(fee == 10000 || fee == 5000 || fee == 3000 || fee == 1000 || fee == 500 || fee == 300 || fee == 100 || fee == 50 || fee == 10, "Invalid fee");
        int24 tickUpper = tickLower + (TICK_SPACING_MULTIPLIER * tickMultiplier);
        owner.callAllocate(vaultAddress, amount, token0, token1, address(lpStrategy), tickLower, tickUpper, fee);
    }

    function owner_doAllocateFixedTickRange(uint256 amount, address token0, address token1) public {
        owner_doAllocate(amount, token0, token1, TICK_LOWER_CONFIG, 20, 10_000);
    }

    function owner_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount, uint24 fee) public {        
        require(fee == 10_000 || fee == 5_000 || fee == 3_000 || fee == 1_000 || fee == 500 || fee == 300 || fee == 100 || fee == 50 || fee == 10, "Invalid fee");
        owner.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount, fee);
    }

    function bighandplayer_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount, uint24 fee) public {
        require(fee == 10_000 || fee == 5_000 || fee == 3_000 || fee == 1_000 || fee == 500 || fee == 300 || fee == 100 || fee == 50 || fee == 10, "Invalid fee");
        bighandplayer.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount, fee);
    }

    // function assertme() public {
    //     // owner_doAllocate(0.1 ether, TOKEN_PRINCIPAL, TOKEN_ANOTHER, -80_000, -10_000);
    //     AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();              
    //     emit LogUint256("vaultAssets.length", vaultAssets.length);
    //     bighandplayer_doSwap(true, 1 ether, 10_000);
    //     assert( vaultAssets.length == 2);
    // }

}


