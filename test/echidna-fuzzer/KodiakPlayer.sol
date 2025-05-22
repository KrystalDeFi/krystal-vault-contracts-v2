pragma solidity ^0.8.28;

import "./Player.sol";
import { IKodiakIslandStrategy } from "../../contracts/interfaces/strategies/kodiak/IKodiakIslandStrategy.sol";
import { IKodiakIsland } from "../../contracts/interfaces/strategies/kodiak/IKodiakIsland.sol";
import { AssetLib } from "../../contracts/libraries/AssetLib.sol";
import { ICommon } from "../../contracts/interfaces/ICommon.sol";

contract KodiakPlayer is Player {
    // Kodiak-specific constants
    address constant REWARD_VAULT = 0x3Be1bE98eFAcA8c1Eb786Cbf38234c84B5052EeB;
    address constant WBERA = 0x6969696969696969696969696969696969696969;
    address constant BGT = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
    address constant OTHER_TOKEN = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;
    address constant REWARD_VAULT_FACTORY = 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8;

    constructor() payable Player() {}

    function callKodiakAllocate(
        address vaultAddress,
        uint256 principalTokenAmount,
        IKodiakIslandStrategy strategy
    ) public {
        IVault vault = IVault(payable(vaultAddress));
        
        AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
        assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WBERA, 0, principalTokenAmount);

        bytes memory data = abi.encode(
            ICommon.Instruction({
                instructionType: uint8(IKodiakIslandStrategy.InstructionType.SwapAndStake),
                params: abi.encode(IKodiakIslandStrategy.SwapAndStakeParams({ bgtRewardVault: REWARD_VAULT }))
            })
        );
            
        vault.allocate(assets, strategy, 0, data);
    }

    function callKodiakWithdraw(
        address vaultAddress,
        uint256 minPrincipalAmount,
        IKodiakIslandStrategy strategy
    ) public {
        IVault vault = IVault(payable(vaultAddress));
        
        AssetLib.Asset[] memory inventory = vault.getInventory();
        AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
        
        // Find the reward vault token in inventory
        for (uint256 i = 0; i < inventory.length; i++) {
            if (inventory[i].token == REWARD_VAULT) {
                assets[0] = inventory[i];
                break;
            }
        }

        bytes memory data = abi.encode(
            ICommon.Instruction({
                instructionType: uint8(IKodiakIslandStrategy.InstructionType.WithdrawAndSwap),
                params: abi.encode(IKodiakIslandStrategy.WithdrawAndSwapParams({ minPrincipalAmount: minPrincipalAmount }))
            })
        );
            
        vault.allocate(assets, strategy, 0, data);
    }
} 
