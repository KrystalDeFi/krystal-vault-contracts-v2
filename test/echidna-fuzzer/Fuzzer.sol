pragma solidity ^0.8.0;

import "./Player.sol";
import "./IHevm.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";

import "./Config.sol";

contract VaultFuzzer {
    
    event LogUint256(string, uint256);
    event LogAddress(string, address);
    event LogString(string);

    bool setupDone = false;

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
        
        IERC20(USDC).transfer(address(owner), 3000 * 10 ** 6);   // decimal of USDC is 6
        IERC20(WETH).transfer(address(owner), 2 ether);   // decimal of WETH is 18

        IERC20(USDC).transfer(address(player1), 3000 * 10 ** 6);   // decimal of USDC is 6
        IERC20(WETH).transfer(address(player1), 2 ether);   // decimal of WETH is 18

        IERC20(USDC).transfer(address(player2), 3000 * 10 ** 6);   // decimal of USDC is 6
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


    // function test_some_invariant_log(uint256 someValue) public {
    
    //     emit LogUint256("someValue", someValue + 15);
    //     emit LogString("we're hereeeee");
    //     assert( 1 == 0);
    // }

    // function assertWETHBalancePlayer1() public {
    //     // require(setupDone);
    //     assert(IERC20(WETH).balanceOf(address(player1)) >= 2 ether);
    // }


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

    function player2_doDepositPrincipalToken(uint256 amount) public {
        player2.callDeposit(vaultAddress, amount, WETH);
    }

    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }

    // function owner_doAllocate(uint256 principalTokenAmount, IStrategy strategy, uint64 gasFeeX64, bytes calldata data) public {
    //     AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    //     assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, principalTokenAmount);

    //     vault.allocate(assets, strategy, gasFeeX64, data);
    //     AssetLib.Asset[] memory vaultAssets = vault.getInventory();
    //     assert(vaultAssets.length < 2);
    // }

    // function owner_doAllocate(uint256 principalTokenAmount) public {
    function owner_doAllocate(uint256 principalTokenAmount) public {
        owner_doDepositPrincipalToken(principalTokenAmount);
        owner.callAllocate(vaultAddress, principalTokenAmount, WETH, USDC, configManagerAddress);        
        AssetLib.Asset[] memory vaultAssets = Vault(payable(vaultAddress)).getInventory();        
        assert(vaultAssets.length > 1);
    }

    // function failed() public {
    //     assert(Vault(payable(vaultAddress)).getTotalValue() == 0 ether);
    // }

    function assets_length() public {
        AssetLib.Asset[] memory vaultAssets = Vault(payable(vaultAddress)).getInventory();
        assert(vaultAssets.length == 1);
    }

    // function deposit_and_withdraw_only(uint256 amount) public {
    //     uint256 ownerWETHBefore = WETH.balanceOf(address(owner));        
        
    //     uint256 sharesDelta = owner.callDeposit(vaultAddress, amount, WETH);
    //     owner.callWithdraw(vaultAddress, sharesDelta, 0);

    //     // it is expected than the owner cant earn more than the initial amount after the deposit and withdraw
    //     assert( WETH.balanceOf(address(owner)) <= ownerWETHBefore );

    //     uint256 player1WETHBefore = WETH.balanceOf(address(player1));
    //     uint256 player1SharesDelta = player1.callDeposit(vaultAddress, amount, WETH);
    //     player1.callWithdraw(vaultAddress, player1SharesDelta, 0);

    //     // it is expected than the player1 cant earn more than the initial amount after the deposit and withdraw
    //     assert( WETH.balanceOf(address(player1)) <= player1WETHBefore );
    // }

    // function deposit_withdraw_empty_vault() public {
    //     require(vault.totalSupply() == 0);     // in this case, no one has never deposited into the vault

    //     uint256 ownerWETHBefore = WETH.balanceOf(address(owner));
    //     uint256 ownerSharesDelta = owner.callDeposit(vaultAddress, 1 ether, WETH);
    //     owner.callWithdraw(vaultAddress, ownerSharesDelta, 0);
        
    //     assert( WETH.balanceOf(address(owner)) == ownerWETHBefore );    // it is expected that the owner has not earned or lost any amount
    // }

}
