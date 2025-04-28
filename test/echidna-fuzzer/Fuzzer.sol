pragma solidity ^0.8.0;

import "./Player.sol";
import "./MockERC20Token.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHevm {
    function warp(uint256 newTimestamp) external;
    function roll(uint256 newNumber) external;
}

contract VaultFuzzer {
    Player public owner;
    Player public player1;
    Player public player2;
    
    MockERC20Token public tokenETH;
    MockERC20Token public tokenUSD;
    VaultFactory public vaultFactory;
    address public vaultAddress;
    Vault public vault;    
    ConfigManager public configManager;

    address constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    IHevm hevm = IHevm(HEVM_ADDRESS);

    constructor() payable {
        owner = new Player();
        tokenETH = new MockERC20Token();
        tokenUSD = new MockERC20Token();

        tokenETH.transfer(address(owner), 1 ether);
        tokenUSD.transfer(address(owner), 1 ether);

        player1 = new Player();
        tokenETH.transfer(address(player1), 1 ether);
        tokenUSD.transfer(address(player1), 1 ether);

        player2 = new Player();
        tokenETH.transfer(address(player2), 1 ether);
        tokenUSD.transfer(address(player2), 1 ether);

        address[] memory whitelistAutomator = new address[](1);
        whitelistAutomator[0] = address(player1);

        address[] memory typedTokens = new address[](2);
        typedTokens[0] = address(tokenETH);
        typedTokens[1] = address(tokenUSD);

        uint256[] memory typedTokenTypes = new uint256[](2);
        typedTokenTypes[0] = uint256(1);
        typedTokenTypes[1] = uint256(1);

        configManager = new ConfigManager(address(owner), whitelistAutomator, typedTokens, typedTokenTypes);

        Vault vaultImplementation = new Vault();
        vaultFactory = new VaultFactory(address(owner), address(tokenETH), address(configManager), address(vaultImplementation));
    
        ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
            name: "Test Public Vault",
            symbol: "TV",
            principalTokenAmount: 0,
            config: ICommon.VaultConfig({
                allowDeposit: true,
                rangeStrategyType: 0,
                tvlStrategyType: 0,
                principalToken: address(tokenETH),
                supportedAddresses: new address[](0)
            })
        });

        // Call createVault through the owner contract
        vaultAddress = owner.callCreateVault(address(vaultFactory), params);
        vault = Vault(payable(vaultAddress));

        player1.callDepositWETH(1 ether);        

    }

    function assertWETHBalance() public {
        assert(IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).balanceOf(address(0xF51D0C3D466b1B0A763031970276047B4a9338E5)) == 1 ether);
    }

    function assertUSDCBalance() public {
        assert(IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).balanceOf(address(0xF51D0C3D466b1B0A763031970276047B4a9338E5)) == 0);
    }


    // function assert_fork_no() public {
    //     uint256 forkId = hevm.activeFork();
    //     assert(forkId == 0);
    // }

    function owner_doDeposit(uint256 amount) public {
        owner.callDeposit(vaultAddress, amount, tokenETH);
    }

    function owner_doWithdraw(uint256 shares) public {
        owner.callWithdraw(vaultAddress, shares, 0);
    }

    function player1_doDeposit(uint256 amount) public {
        player1.callDeposit(vaultAddress, amount, tokenETH);
    }

    function player1_doWithdraw(uint256 shares) public {
        player1.callWithdraw(vaultAddress, shares, 0);
    }

    function player2_doDeposit(uint256 amount) public {
        player2.callDeposit(vaultAddress, amount, tokenETH);
    }

    function player2_doWithdraw(uint256 shares) public {
        player2.callWithdraw(vaultAddress, shares, 0);
    }

    function owner_doAllocate(uint256 principalTokenAmount, IStrategy strategy, uint64 gasFeeX64, bytes calldata data) public {
        AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
        assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), address(tokenETH), 0, principalTokenAmount);

        vault.allocate(assets, strategy, gasFeeX64, data);
        AssetLib.Asset[] memory vaultAssets = vault.getInventory();
        assert(vaultAssets.length < 2);
    }

    function assets_length() public {
        AssetLib.Asset[] memory vaultAssets = vault.getInventory();
        assert(vaultAssets.length == 1);
    }

    function deposit_and_withdraw_only(uint256 amount) public {
        uint256 ownerTokenEthBefore = tokenETH.balanceOf(address(owner));        
        
        uint256 sharesDelta = owner.callDeposit(vaultAddress, amount, tokenETH);
        owner.callWithdraw(vaultAddress, sharesDelta, 0);

        // it is expected than the owner cant earn more than the initial amount after the deposit and withdraw
        assert( tokenETH.balanceOf(address(owner)) <= ownerTokenEthBefore );

        uint256 player1TokenEthBefore = tokenETH.balanceOf(address(player1));
        uint256 player1SharesDelta = player1.callDeposit(vaultAddress, amount, tokenETH);
        player1.callWithdraw(vaultAddress, player1SharesDelta, 0);

        // it is expected than the player1 cant earn more than the initial amount after the deposit and withdraw
        assert( tokenETH.balanceOf(address(player1)) <= player1TokenEthBefore );
    }

    function deposit_withdraw_empty_vault() public {
        require(vault.totalSupply() == 0);     // in this case, no one has never deposited into the vault

        uint256 ownerTokenEthBefore = tokenETH.balanceOf(address(owner));
        uint256 ownerSharesDelta = owner.callDeposit(vaultAddress, 1 ether, tokenETH);
        owner.callWithdraw(vaultAddress, ownerSharesDelta, 0);
        
        assert( tokenETH.balanceOf(address(owner)) == ownerTokenEthBefore );    // it is expected that the owner has not earned or lost any amount
    }

}
