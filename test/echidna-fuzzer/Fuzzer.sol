pragma solidity ^0.8.0;

import "./Player.sol";
import "./MockERC20Token.sol";
import "../../contracts/core/VaultFactory.sol";
import "../../contracts/core/Vault.sol";
import "../../contracts/core/ConfigManager.sol";

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
    }

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

    function deposit_and_withdraw_one_owner_only(uint256 amount) public {
        uint256 ownerTokenEthBefore = tokenETH.balanceOf(address(owner));        
        
        uint256 sharesDelta = owner.callDeposit(vaultAddress, amount, tokenETH);
        owner.callWithdraw(vaultAddress, sharesDelta, 0);

        // it is expected than the owner cant earn more than the initial amount after the deposit and withdraw
        assert( tokenETH.balanceOf(address(owner)) <= ownerTokenEthBefore );
    }

}
