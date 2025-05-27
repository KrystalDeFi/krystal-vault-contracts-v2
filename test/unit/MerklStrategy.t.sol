// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/strategies/merkl/MerklStrategy.sol";
import "../../contracts/core/ConfigManager.sol";
import "../../test/TestCommon.t.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/interfaces/ICommon.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Mock contracts for testing
contract MockMerklDistributor {
  function claim(address[] calldata users, address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata)
    external
  {
    // Just transfer the tokens to simulate a successful claim
    for (uint256 i = 0; i < users.length; i++) {
      MockERC20(tokens[i]).mint(address(this), amounts[i]);
      MockERC20(tokens[i]).transfer(users[i], amounts[i]);
    }
  }
}

contract MockERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    _mint(msg.sender, 1_000_000 * 10 ** 18);
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract MockSwapRouter {
  using SafeERC20 for IERC20;

  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    require(tokenIn != tokenOut);
    // Transfer tokens to simulate a swap
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
  }
}

contract MerklStrategyTest is TestCommon {
  MerklStrategy public strategy;
  ConfigManager public configManager;
  MockMerklDistributor public distributor;
  MockERC20 public rewardToken;
  MockERC20 public principalToken;
  MockSwapRouter public swapRouter;

  address public owner = address(0x1);
  address public user = address(0x2);
  address public whitelistedSigner;
  uint256 public whitelistedSignerPrivateKey;
  uint256 public nonWhitelistedSignerPrivateKey;
  address public nonWhitelistedSigner;

  function setUp() public {
    // Generate test keys
    whitelistedSignerPrivateKey = 0xA11CE;
    whitelistedSigner = vm.addr(whitelistedSignerPrivateKey);
    nonWhitelistedSignerPrivateKey = 0xB0B;
    nonWhitelistedSigner = vm.addr(nonWhitelistedSignerPrivateKey);

    // Deploy mock tokens
    rewardToken = new MockERC20("Reward Token", "RWD");
    principalToken = new MockERC20("Principal Token", "PRIN");

    // Deploy mock distributor and fund it with reward tokens
    distributor = new MockMerklDistributor();
    rewardToken.transfer(address(distributor), 100_000 * 10 ** 18);

    // Deploy mock swap router and fund it with principal tokens
    swapRouter = new MockSwapRouter();
    principalToken.transfer(address(swapRouter), 100_000 * 10 ** 18);

    address[] memory typedTokens = new address[](0);
    uint256[] memory typedTokenTypes = new uint256[](0);
    address[] memory whitelistAutomator = new address[](0);
    // Deploy config manager
    configManager = new ConfigManager();
    configManager.initialize(
      owner,
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

    // Whitelist the swap router
    address[] memory routers = new address[](1);
    routers[0] = address(swapRouter);
    vm.prank(owner);
    configManager.whitelistSwapRouter(routers, true);

    // Whitelist the signer
    address[] memory signers = new address[](1);
    signers[0] = whitelistedSigner;
    vm.prank(owner);
    configManager.whitelistSigner(signers, true);

    // Deploy the strategy
    strategy = new MerklStrategy(address(configManager));
  }

  function testValueOf() public view {
    AssetLib.Asset memory asset;
    assertEq(strategy.valueOf(asset, address(0)), 0, "valueOf should always return 0");
  }

  function testClaimAndSwap() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    uint256 expectedSwapOut = 900 * 10 ** 18; // 90% of reward amount as an example
    bytes32[] memory proofs = new bytes32[](0); // Empty proofs for mock
    uint32 deadline = uint32(block.timestamp + 1 hours);

    // Encode swap data (for the mock router)
    bytes memory swapData = abi.encodeWithSelector(
      MockSwapRouter.swap.selector, address(rewardToken), address(principalToken), rewardAmount, expectedSwapOut
    );

    // Create message hash for signing
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(rewardToken),
        rewardAmount,
        proofs,
        address(swapRouter),
        swapData,
        expectedSwapOut - 10 * 10 ** 18,
        deadline
      )
    );

    // Sign the message
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(whitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(rewardToken),
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(swapRouter),
      swapData: swapData,
      amountOutMin: expectedSwapOut - 10 * 10 ** 18,
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    AssetLib.Asset[] memory outputAssets = strategy.convert(inputAssets, vaultConfig, feeConfig, data);

    // Verify results
    assertEq(outputAssets.length, 2, "Should return 2 assets");

    // First asset should be the reward token with 0 amount (all swapped)
    assertEq(address(outputAssets[0].token), address(rewardToken), "First asset should be reward token");
    assertEq(outputAssets[0].amount, 0, "Reward token amount should be 0 after swap");

    // Second asset should be the principal token with the swapped amount
    assertEq(address(outputAssets[1].token), address(principalToken), "Second asset should be principal token");
    assertEq(outputAssets[1].amount, expectedSwapOut, "Principal token amount should match expected swap output");
  }

  function testRevertWhenSwapRouterNotWhitelisted() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Deploy a non-whitelisted router
    MockSwapRouter nonWhitelistedRouter = new MockSwapRouter();
    principalToken.transfer(address(nonWhitelistedRouter), 100_000 * 10 ** 18);

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    uint256 expectedSwapOut = 900 * 10 ** 18;
    bytes32[] memory proofs = new bytes32[](0);
    uint32 deadline = uint32(block.timestamp + 1 hours);

    // Encode swap data
    bytes memory swapData = abi.encodeWithSelector(
      MockSwapRouter.swap.selector, address(rewardToken), address(principalToken), rewardAmount, expectedSwapOut
    );

    // Create message hash for signing
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(rewardToken),
        rewardAmount,
        proofs,
        address(nonWhitelistedRouter),
        swapData,
        expectedSwapOut - 10 * 10 ** 18,
        deadline
      )
    );

    // Sign the message
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(whitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters with non-whitelisted router
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(rewardToken),
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(nonWhitelistedRouter),
      swapData: swapData,
      amountOutMin: expectedSwapOut - 10 * 10 ** 18,
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert - should revert
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    vm.expectRevert(ICommon.InvalidSwapRouter.selector);
    strategy.convert(inputAssets, vaultConfig, feeConfig, data);
  }

  function testRevertWhenAmountOutTooLow() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    uint256 actualSwapOut = 800 * 10 ** 18;
    bytes32[] memory proofs = new bytes32[](0);
    uint32 deadline = uint32(block.timestamp + 1 hours);
    uint256 minAmountOut = 900 * 10 ** 18; // Higher than actual output

    // Encode swap data
    bytes memory swapData = abi.encodeWithSelector(
      MockSwapRouter.swap.selector, address(rewardToken), address(principalToken), rewardAmount, actualSwapOut
    );

    // Create message hash for signing
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(rewardToken),
        rewardAmount,
        proofs,
        address(swapRouter),
        swapData,
        minAmountOut,
        deadline
      )
    );

    // Sign the message
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(whitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters with high minimum out
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(rewardToken),
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(swapRouter),
      swapData: swapData,
      amountOutMin: minAmountOut,
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert - should revert due to insufficient output
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    vm.expectRevert(IMerklStrategy.NotEnoughAmountOut.selector);
    strategy.convert(inputAssets, vaultConfig, feeConfig, data);
  }

  function testRevertOnInvalidInstructionType() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Create an instruction with invalid type (99)
    ICommon.Instruction memory instruction = ICommon.Instruction({ instructionType: 99, params: bytes("") });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert - should revert due to invalid instruction type
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    vm.expectRevert(ICommon.InvalidInstructionType.selector);
    strategy.convert(inputAssets, vaultConfig, feeConfig, data);
  }

  function testRevertOnInvalidSigner() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    uint256 expectedSwapOut = 900 * 10 ** 18;
    bytes32[] memory proofs = new bytes32[](0);
    uint32 deadline = uint32(block.timestamp + 1 hours);

    // Encode swap data
    bytes memory swapData = abi.encodeWithSelector(
      MockSwapRouter.swap.selector, address(rewardToken), address(principalToken), rewardAmount, expectedSwapOut
    );

    // Create message hash for signing
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(rewardToken),
        rewardAmount,
        proofs,
        address(swapRouter),
        swapData,
        expectedSwapOut - 10 * 10 ** 18,
        deadline
      )
    );

    // Sign the message with non-whitelisted signer
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(nonWhitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(rewardToken),
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(swapRouter),
      swapData: swapData,
      amountOutMin: expectedSwapOut - 10 * 10 ** 18,
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert - should revert due to invalid signer
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    vm.expectRevert(ICommon.InvalidSigner.selector);
    strategy.convert(inputAssets, vaultConfig, feeConfig, data);
  }

  function testFeeTakingMechanism() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config with all fee types
    address vaultOwner = address(0x3);
    address platformRecipient = address(0x4);
    address gasRecipient = address(0x5);

    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 100, // 1%
      vaultOwner: vaultOwner,
      platformFeeBasisPoint: 200, // 2%
      platformFeeRecipient: platformRecipient,
      gasFeeX64: 184_467_440_737_095_520, // ~1% in Q64
      gasFeeRecipient: gasRecipient
    });

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    uint256 expectedSwapOut = 900 * 10 ** 18;
    bytes32[] memory proofs = new bytes32[](0);
    uint32 deadline = uint32(block.timestamp + 1 hours);

    // Encode swap data
    bytes memory swapData = abi.encodeWithSelector(
      MockSwapRouter.swap.selector, address(rewardToken), address(principalToken), rewardAmount, expectedSwapOut
    );

    // Create message hash for signing
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(rewardToken),
        rewardAmount,
        proofs,
        address(swapRouter),
        swapData,
        expectedSwapOut - 10 * 10 ** 18,
        deadline
      )
    );

    // Sign the message
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(whitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(rewardToken),
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(swapRouter),
      swapData: swapData,
      amountOutMin: expectedSwapOut - 10 * 10 ** 18,
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Get initial balances
    uint256 initialVaultOwnerBalance = principalToken.balanceOf(vaultOwner);
    uint256 initialPlatformBalance = principalToken.balanceOf(platformRecipient);
    uint256 initialGasRecipientBalance = principalToken.balanceOf(gasRecipient);

    // Call convert
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    AssetLib.Asset[] memory outputAssets = strategy.convert(inputAssets, vaultConfig, feeConfig, data);

    // Calculate expected fees
    uint256 expectedVaultOwnerFee = expectedSwapOut * 100 / 10_000; // 1%
    uint256 expectedPlatformFee = expectedSwapOut * 200 / 10_000; // 2%
    uint256 expectedGasFee = expectedSwapOut * 184_467_440_737_095_520 / (2 ** 64); // ~1%

    // Verify fee transfers
    assertEq(
      principalToken.balanceOf(vaultOwner) - initialVaultOwnerBalance,
      expectedVaultOwnerFee,
      "Vault owner fee not transferred correctly"
    );
    assertEq(
      principalToken.balanceOf(platformRecipient) - initialPlatformBalance,
      expectedPlatformFee,
      "Platform fee not transferred correctly"
    );
    assertEq(
      principalToken.balanceOf(gasRecipient) - initialGasRecipientBalance,
      expectedGasFee,
      "Gas fee not transferred correctly"
    );

    // Verify output amount is reduced by fees
    uint256 totalFees = expectedVaultOwnerFee + expectedPlatformFee + expectedGasFee;
    assertEq(outputAssets[1].amount, expectedSwapOut - totalFees, "Output amount should be reduced by total fees");
  }

  function testRevertOnExpiredSignature() public {
    // Create vault config
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    uint256 expectedSwapOut = 900 * 10 ** 18;
    bytes32[] memory proofs = new bytes32[](0);
    uint32 deadline = uint32(block.timestamp - 1); // Expired deadline

    // Encode swap data
    bytes memory swapData = abi.encodeWithSelector(
      MockSwapRouter.swap.selector, address(rewardToken), address(principalToken), rewardAmount, expectedSwapOut
    );

    // Create message hash for signing
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(rewardToken),
        rewardAmount,
        proofs,
        address(swapRouter),
        swapData,
        expectedSwapOut - 10 * 10 ** 18,
        deadline
      )
    );

    // Sign the message
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(whitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(rewardToken),
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(swapRouter),
      swapData: swapData,
      amountOutMin: expectedSwapOut - 10 * 10 ** 18,
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert - should revert due to expired signature
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    vm.expectRevert(ICommon.SignatureExpired.selector);
    strategy.convert(inputAssets, vaultConfig, feeConfig, data);
  }

  function testClaimWithoutSwap() public {
    // Create vault config with principal token same as reward token
    ICommon.VaultConfig memory vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: address(principalToken),
      supportedAddresses: new address[](0)
    });

    // Create fee config
    ICommon.FeeConfig memory feeConfig = ICommon.FeeConfig({
      vaultOwnerFeeBasisPoint: 0,
      vaultOwner: address(0),
      platformFeeBasisPoint: 0,
      platformFeeRecipient: address(0),
      gasFeeX64: 0,
      gasFeeRecipient: address(0)
    });

    // Prepare claim parameters
    uint256 rewardAmount = 1000 * 10 ** 18;
    bytes32[] memory proofs = new bytes32[](0);
    uint32 deadline = uint32(block.timestamp + 1 hours);

    // Create message hash for signing - note we don't include swap parameters since we're not swapping
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        address(distributor),
        address(principalToken), // Using principal token as reward token
        rewardAmount,
        proofs,
        address(0), // No swap router needed
        bytes(""), // No swap data needed
        uint256(0), // No minimum amount out needed
        deadline
      )
    );

    // Sign the message
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(whitelistedSignerPrivateKey, messageHash);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Encode claim and swap parameters
    IMerklStrategy.ClaimAndSwapParams memory claimParams = IMerklStrategy.ClaimAndSwapParams({
      distributor: address(distributor),
      token: address(principalToken), // Using principal token as reward token
      amount: rewardAmount,
      proof: proofs,
      swapRouter: address(0), // No swap router needed
      swapData: bytes(""), // No swap data needed
      amountOutMin: 0, // No minimum amount out needed
      deadline: deadline,
      signature: signature
    });

    // Encode instruction
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimParams)
    });

    // Encode the full data
    bytes memory data = abi.encode(instruction);

    // Call convert
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](0);
    AssetLib.Asset[] memory outputAssets = strategy.convert(inputAssets, vaultConfig, feeConfig, data);

    // Verify results
    assertEq(outputAssets.length, 1, "Should return 1 asset");
    assertEq(address(outputAssets[0].token), address(principalToken), "Output token should be principal token");
    assertEq(outputAssets[0].amount, rewardAmount, "Output amount should match reward amount");
  }
}
