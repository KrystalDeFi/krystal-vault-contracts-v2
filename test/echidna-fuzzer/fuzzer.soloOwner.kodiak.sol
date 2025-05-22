/*

    In this fuzzer, the owner initializes the vault and the player1 & player 2 deposits. The bighand player swapped with an amount.
    Later, the owner is trying to take almost all the balance of the vault.
*/

pragma solidity ^0.8.0;

import "./KodiakPlayer.sol";
import "./IHevm.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";
import { KodiakIslandStrategy } from "../../contracts/strategies/kodiak/KodiakIslandStrategy.sol";
import { IKodiakIslandStrategy } from "../../contracts/interfaces/strategies/kodiak/IKodiakIslandStrategy.sol";
import { IKodiakIsland } from "../../contracts/interfaces/strategies/kodiak/IKodiakIsland.sol";

import "./Config.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";

address constant TOKEN_PRINCIPAL = 0x6969696969696969696969696969696969696969;    // WBERA on berachain
address constant BGT = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
address constant TOKEN_ANOTHER = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;
address constant REWARD_VAULT_FACTORY = 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8;
address constant BERA_BANK_ADDRESS = 0x425F1EdD3D2A3b1097E23910be85563594D4EF77;
uint256 constant BLOCK_NUMBER = 5_345_858;
// uint256 constant BLOCK_TIMESTAMP = 1745814599;
uint256 constant PLAYER_INITIAL_PTOKEN_BALANCE = 100 ether;

contract VaultFuzzerSoloOwnerKodiak {
    
    event LogUint256(string, uint256);
    event LogAddress(string, address);
    event LogString(string);    

    KodiakPlayer public owner;
    KodiakPlayer public player1;
    KodiakPlayer public player2;
    KodiakPlayer public bighandplayer;
    
    VaultFactory public vaultFactory;
    address public vaultAddress;
    address public configManagerAddress;    
    KodiakIslandStrategy public lpStrategy;
    // IKodiakIsland public kodiakIsland;
    
    IHevm hevm = IHevm(HEVM_ADDRESS);

    constructor() payable {
        owner = new KodiakPlayer();                
        player1 = new KodiakPlayer();        
        player2 = new KodiakPlayer();
        bighandplayer = new KodiakPlayer();
        hevm.roll(BLOCK_NUMBER);
        // hevm.warp(BLOCK_TIMESTAMP);

        hevm.startPrank(BERA_BANK_ADDRESS);
                
        IERC20(TOKEN_PRINCIPAL).transfer(address(owner), PLAYER_INITIAL_PTOKEN_BALANCE);   // decimal of TOKEN_PRINCIPAL is 18
        IERC20(TOKEN_PRINCIPAL).transfer(address(player1), PLAYER_INITIAL_PTOKEN_BALANCE);   // decimal of TOKEN_PRINCIPAL is 18        
        IERC20(TOKEN_PRINCIPAL).transfer(address(player2), PLAYER_INITIAL_PTOKEN_BALANCE);   // decimal of TOKEN_PRINCIPAL is 18
        IERC20(TOKEN_PRINCIPAL).transfer(address(bighandplayer), 1000 ether);

        hevm.stopPrank();
    
        address[] memory whitelistNfpms = new address[](1);
        whitelistNfpms[0] = address(NFPM_ON_ETH_MAINNET);
        
        PoolOptimalSwapper swapper = new PoolOptimalSwapper();
        
        LpFeeTaker feeTaker = new LpFeeTaker();

        lpStrategy = new KodiakIslandStrategy(address(swapper), REWARD_VAULT_FACTORY, address(feeTaker), BGT, TOKEN_PRINCIPAL);
        address[] memory strategies = new address[](1);
        strategies[0] = address(lpStrategy);


        address[] memory typedTokens = new address[](2);
        typedTokens[0] = TOKEN_PRINCIPAL;
        typedTokens[1] = TOKEN_ANOTHER;

        uint256[] memory typedTokenTypes = new uint256[](2);
        typedTokenTypes[0] = uint256(1);
        typedTokenTypes[1] = uint256(1);

        address[] memory whitelistAutomator = new address[](1);
        whitelistAutomator[0] = address(player1);

        ConfigManager configManager = new ConfigManager();
        configManager.initialize(
            address(owner),
            strategies,
            new address[](0),
            whitelistAutomator,
            new address[](0),
            typedTokens,
            typedTokenTypes,
            100,
            50,
            50,
            address(0),
            new address[](0),
            new address[](0),
            new bytes[](0)
        );        
        configManagerAddress = address(configManager);        


        // Setup common configurations
        ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
            allowDeposit: true,
            rangeStrategyType: 0,
            tvlStrategyType: 0,
            principalToken: TOKEN_PRINCIPAL,
            supportedAddresses: new address[](0)
        });

        Vault vaultImplementation = new Vault();
        vaultFactory = new VaultFactory();
        vaultFactory.initialize(address(owner), TOKEN_PRINCIPAL, configManagerAddress, address(vaultImplementation));    

        ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
            name: "Kodiak Island Vault",
            symbol: "KIV",
            principalTokenAmount: 0,
            config: vaultConfig
        });

        // ---------------------        

        // Call createVault through the owner contract
        vaultAddress = owner.callCreateVault(address(vaultFactory), params);

        owner.callDeposit(vaultAddress, 50 ether, TOKEN_PRINCIPAL);
        player1.callDeposit(vaultAddress, 50 ether, TOKEN_PRINCIPAL);
        player2.callDeposit(vaultAddress, 50 ether, TOKEN_PRINCIPAL);
        // owner.callKodiakAllocate(vaultAddress, 1.5 ether, address(lpStrategy));
        owner_doAllocateFixedTickRange(100 ether);
        // // owner.callAllocate(vaultAddress, 1.5 ether, TOKEN_PRINCIPAL, TOKEN_ANOTHER, address(lpStrategy));
        // bighandplayer.doSwap(TOKEN_PRINCIPAL, TOKEN_ANOTHER, 30 ether);

    }

    function assertPrincipleTokenBalanceOwner() public {
        uint256 wethBalance = IERC20(TOKEN_PRINCIPAL).balanceOf(address(owner));
        emit LogUint256("wethBalance of owner", wethBalance);
        assert(wethBalance > PLAYER_INITIAL_PTOKEN_BALANCE);        
    }
    
    // function owner_doWithdraw(uint256 shares) public {
    //     owner.callWithdraw(vaultAddress, shares, 0);
    // }

    // function player1_doWithdraw(uint256 shares) public {
    //     player1.callWithdraw(vaultAddress, shares, 0);
    // }

    // function owner_doDepositPrincipalToken(uint256 amount) public {
    //     owner.callDeposit(vaultAddress, amount, TOKEN_PRINCIPAL);
    // }

    // function owner_doDepositAnotherToken(uint256 amount) public {
    //     owner.callDeposit(vaultAddress, amount, TOKEN_ANOTHER);
    // }    

    // function owner_doAllocate(uint256 amount, address token0, address token1, int24 tickLower, int24 tickUpper) public {
    //     owner.callAllocate(vaultAddress, amount, token0, token1, address(lpStrategy), tickLower, tickUpper);
    // }

    function owner_doAllocateFixedTickRange(uint256 amount) public {
        owner.callKodiakAllocate(vaultAddress, amount, lpStrategy);        
    }

    // function owner_doSwap(bool token0AddressIsTokenPrinciple, uint256 token0Amount) public {        
    //     owner.doSwap(token0AddressIsTokenPrinciple ? TOKEN_PRINCIPAL : TOKEN_ANOTHER, token0AddressIsTokenPrinciple ? TOKEN_ANOTHER : TOKEN_PRINCIPAL, token0Amount);
    // }

    // // TODO
    // // [x] owner reallocates
    // // [ ] owner reconfigs
    // // [ ] owner harvest
    // // [ ] owner change allowDeposit config


}


//     function assertme() public {
//         // owner_doAllocate(0.1 ether, TOKEN_PRINCIPAL, TOKEN_ANOTHER, -80_000, -10_000);
//         AssetLib.Asset[] memory vaultAssets = IVault(payable(vaultAddress)).getInventory();              
//         emit LogUint256("vaultAssets.length", vaultAssets.length);
//         assert( vaultAssets.length == 2);
//     }
