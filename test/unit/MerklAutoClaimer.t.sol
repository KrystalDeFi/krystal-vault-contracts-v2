// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/strategies/merkl/MerklAutoClaimer.sol";
import "../../contracts/strategies/merkl/MerklStrategy.sol";
import "../../contracts/interfaces/core/IVault.sol";
import "../../contracts/interfaces/strategies/IMerklStrategy.sol";
import "../../contracts/libraries/AssetLib.sol";
import "../../test/TestCommon.t.sol";

contract MerklAutoClaimerTest is TestCommon {
  MerklAutoClaimer public autoClaimer;
  MerklStrategy public strategy;
  IVault public vault;
  address public owner = makeAddr("owner");
  address public operator = makeAddr("operator");
  address public user = makeAddr("user");
  address public token = makeAddr("rewardToken");
  address public principalToken = makeAddr("principalToken");

  function setUp() public {
    // Deploy test contracts
    strategy = new MerklStrategy(address(this)); // Using test contract as config manager
    address[] memory allowedStrategies = new address[](1);
    allowedStrategies[0] = address(strategy);
    autoClaimer = new MerklAutoClaimer(allowedStrategies, owner);

    // Setup mock vault
    vault = IVault(makeAddr("vault"));
    vm.mockCall(address(vault), abi.encodeWithSelector(IVault.vaultOwner.selector), abi.encode(owner));
  }

  function test_ClaimRewards() public {
    // Prepare claim params
    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(uint32(block.timestamp)) + 1 days,
      signature: _signClaimParams(owner)
    });

    // Verify vault allocate was called
    vm.expectCall(
      address(vault),
      abi.encodeWithSelector(
        IVault.allocate.selector,
        new AssetLib.Asset[](0),
        address(strategy),
        0,
        abi.encode(
          ICommon.Instruction({
            instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
            params: abi.encode(params)
          })
        )
      )
    );

    // Test claim by user
    vm.prank(user);
    autoClaimer.claimRewards(vault, address(strategy), params);
  }

  function test_RevertIf_InvalidStrategy() public {
    address invalidStrategy = makeAddr("invalidStrategy");
    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(block.timestamp) + 1 days,
      signature: _signClaimParams(owner)
    });

    vm.expectRevert(ICommon.InvalidStrategy.selector);
    autoClaimer.claimRewards(vault, invalidStrategy, params);
  }

  function test_GrantRevokeOperator() public {
    // Grant operator
    vm.prank(owner);
    autoClaimer.grantOperator(operator);
    assertTrue(autoClaimer.hasRole(autoClaimer.OPERATOR_ROLE_HASH(), operator));

    // Revoke operator
    vm.prank(owner);
    autoClaimer.revokeOperator(operator);
    assertFalse(autoClaimer.hasRole(autoClaimer.OPERATOR_ROLE_HASH(), operator));
  }

  function test_RevertIf_NonAdminTriesToGrantOperator() public {
    vm.prank(user);
    vm.expectRevert();
    autoClaimer.grantOperator(operator);
  }

  function _signClaimParams(address signer) internal returns (bytes memory) {
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        makeAddr("distributor"),
        token,
        uint256(100 ether),
        new bytes32[](0),
        makeAddr("swapRouter"),
        abi.encode("swap"),
        uint256(90 ether),
        uint32(block.timestamp) + 1 days
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), messageHash);
    return abi.encodePacked(r, s, v);
  }
}
