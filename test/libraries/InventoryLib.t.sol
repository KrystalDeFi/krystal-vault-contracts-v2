// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import { Test } from "forge-std/Test.sol";
import { InventoryLib } from "../../contracts/libraries/InventoryLib.sol";
import { AssetLib } from "../../contracts/libraries/AssetLib.sol";

contract InventoryLibTest is Test {
    using InventoryLib for InventoryLib.Inventory;

    InventoryLib.Inventory internal inventory;
    address constant TOKEN1 = address(0x1);
    address constant TOKEN2 = address(0x2);
    uint256 constant TOKEN_ID1 = 1;
    uint256 constant TOKEN_ID2 = 2;

    function setUp() public {
        // Initialize with some test assets
        AssetLib.Asset memory asset1 = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: TOKEN1,
            tokenId: TOKEN_ID1,
            amount: 100
        });
        
        AssetLib.Asset memory asset2 = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC721,
            strategy: address(0),
            token: TOKEN2,
            tokenId: TOKEN_ID2,
            amount: 1
        });

        inventory.addAsset(asset1);
        inventory.addAsset(asset2);
    }

    function test_AddNewAsset() public {
        AssetLib.Asset memory newAsset = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: address(0x3),
            tokenId: 3,
            amount: 50
        });

        uint256 initialLength = inventory.assets.length;
        inventory.addAsset(newAsset);

        assertEq(inventory.assets.length, initialLength + 1);
        assertEq(inventory.assets[initialLength].amount, 50);
        assertTrue(inventory.contains(address(0x3), 3));
    }

    function test_AddToExistingAsset() public {
        AssetLib.Asset memory additionalAsset = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: TOKEN1,
            tokenId: TOKEN_ID1,
            amount: 50
        });

        uint256 initialLength = inventory.assets.length;
        inventory.addAsset(additionalAsset);

        assertEq(inventory.assets.length, initialLength); // Length shouldn't change
        assertEq(inventory.assets[0].amount, 150); // Amount should increase
    }

    function test_RemoveAsset() public {
        AssetLib.Asset memory toRemove = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: TOKEN1,
            tokenId: TOKEN_ID1,
            amount: 50
        });

        uint256 initialLength = inventory.assets.length;
        inventory.removeAsset(toRemove);

        assertEq(inventory.assets.length, initialLength); // Length stays same
        assertEq(inventory.assets[0].amount, 50); // Amount reduced
    }

    function test_RemoveAssetWithDelete() public {
        AssetLib.Asset memory toRemove = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: TOKEN1,
            tokenId: TOKEN_ID1,
            amount: 100
        });

        uint256 initialLength = inventory.assets.length;
        inventory.removeAsset(toRemove, true);

        assertEq(inventory.assets.length, initialLength - 1);
        assertFalse(inventory.contains(TOKEN1, TOKEN_ID1));
    }

    function test_RemoveAssetByIndex() public {
        uint256 initialLength = inventory.assets.length;
        inventory.removeAsset(0); // Remove first asset

        assertEq(inventory.assets.length, initialLength - 1);
        assertFalse(inventory.contains(TOKEN1, TOKEN_ID1));
    }

    function test_GetAsset() public {
        AssetLib.Asset memory asset = inventory.getAsset(TOKEN1, TOKEN_ID1);
        
        assertEq(asset.amount, 100);
        assertEq(uint256(asset.assetType), uint256(AssetLib.AssetType.ERC20));
    }

    function test_GetAssetRevertsIfNotFound() public {
        vm.expectRevert(InventoryLib.AssetNotFound.selector);
        inventory.getAsset(address(0x999), 999);
    }

    function test_Contains() public {
        assertTrue(inventory.contains(TOKEN1, TOKEN_ID1));
        assertFalse(inventory.contains(address(0x999), 999));
    }

    function test_RemoveAssetRevertsIfInsufficient() public {
        AssetLib.Asset memory toRemove = AssetLib.Asset({
            assetType: AssetLib.AssetType.ERC20,
            strategy: address(0),
            token: TOKEN1,
            tokenId: TOKEN_ID1,
            amount: 101 // More than available
        });

        vm.expectRevert("InventoryLib: insufficient amount");
        inventory.removeAsset(toRemove);
    }
}
