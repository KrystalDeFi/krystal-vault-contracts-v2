pragma solidity ^0.8.0;

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import "../../contracts/core/Vault.sol";
import "./MockERC20Token.sol";

import "forge-std/console.sol";     //forge-test-only
import { Test } from "forge-std/Test.sol";      //forge-test-only

contract Player {
    constructor() payable {
    } 

    function callDeposit(address vault, uint256 amount, MockERC20Token token) public returns (uint256) {
        token.approve(vault, amount);    
        return Vault(payable(vault)).deposit(amount, 0);        
    }

    function callWithdraw(address vault, uint256 shares, uint256 minAmount) public {
        Vault(payable(vault)).withdraw(shares, false, minAmount);
    }

    function callCreateVault(address vaultFactory, ICommon.VaultCreateParams memory params) public returns (address) {
        return IVaultFactory(vaultFactory).createVault(params);
    }
}
