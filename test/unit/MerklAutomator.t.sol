// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/ConfigManager.sol";
import "../../contracts/strategies/merkl/MerklAutomator.sol";
import "../../contracts/strategies/merkl/MerklStrategy.sol";
import "../../contracts/interfaces/core/IVault.sol";
import "../../contracts/interfaces/strategies/IMerklStrategy.sol";
import "../../contracts/libraries/AssetLib.sol";
import "../../test/TestCommon.t.sol";

contract MerklAutomatorTest is TestCommon {
  MerklAutomator public autoClaimer;
  MerklStrategy public strategy;
  IVault public vault;
  uint256 public ownerPrivateKey = 0xABCD;
  address public owner = vm.addr(ownerPrivateKey);
  address public user = makeAddr("user");
  address public token = makeAddr("rewardToken");
  address public principalToken = makeAddr("principalToken");

  function setUp() public {
    ConfigManager configManager = new ConfigManager();
    configManager.initialize(
      owner,
      new address[](0),
      new address[](0),
      new address[](0),
      new address[](0),
      new address[](0),
      new uint256[](0),
      0,
      0,
      0,
      address(0),
      new address[](0),
      new address[](0),
      new bytes[](0)
    );
    address[] memory whitelistedSigners = new address[](1);
    whitelistedSigners[0] = owner;
    vm.startPrank(owner);
    configManager.whitelistSigner(whitelistedSigners, true);
    vm.stopPrank();
    // Deploy test contracts
    strategy = new MerklStrategy(address(this)); // Using test contract as config manager
    address[] memory allowedStrategies = new address[](1);
    allowedStrategies[0] = address(strategy);
    autoClaimer = new MerklAutomator(address(configManager));

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
      signature: _signClaimParams(ownerPrivateKey)
    });

    bytes memory allocateData = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
        params: abi.encode(params)
      })
    );

    // Verify vault allocate was called
    vm.expectCall(
      address(vault),
      abi.encodeWithSelector(IVault.allocate.selector, new AssetLib.Asset[](0), address(strategy), 0, allocateData)
    );

    // Test claim by user
    vm.prank(user);
    autoClaimer.executeAllocate(vault, new AssetLib.Asset[](0), strategy, 0, allocateData, "", "");
  }

  function test_RevertIf_ExpiredSignature() public {
    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(uint32(block.timestamp)) + 1 days, // expired
      signature: _signClaimParams(ownerPrivateKey)
    });

    bytes memory allocateData = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
        params: abi.encode(params)
      })
    );

    skip(2 days); // skip to make signature expired
    vm.expectRevert(ICommon.SignatureExpired.selector);
    vm.prank(user);
    autoClaimer.executeAllocate(vault, new AssetLib.Asset[](0), strategy, 0, allocateData, "", "");
  }

  function test_RevertIf_InvalidSigner() public {
    // Sign with non-whitelisted private key
    uint256 invalidPrivateKey = 12_345;

    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(uint32(block.timestamp)) + 1 days,
      signature: _signClaimParams(invalidPrivateKey)
    });

    bytes memory allocateData = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
        params: abi.encode(params)
      })
    );

    vm.expectRevert(ICommon.InvalidSigner.selector);
    vm.prank(user);
    autoClaimer.executeAllocate(vault, new AssetLib.Asset[](0), strategy, 0, allocateData, "", "");
  }

  function _signClaimParams(uint256 signer) internal returns (bytes memory) {
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
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, messageHash);
    return abi.encodePacked(r, s, v);
  }
}
