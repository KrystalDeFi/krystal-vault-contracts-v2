// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// ── Base mainnet addresses ────────────────────────────────────────────────────
address constant SV_WETH    = 0x4200000000000000000000000000000000000006;
address constant SV_USDC    = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant SV_NFPM    = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1; // Uniswap V3 on Base
address constant SV_V3UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

// ── Fork pin ──────────────────────────────────────────────────────────────────
uint256 constant SV_BLOCK_NUMBER    = 36_953_600;
uint256 constant SV_BLOCK_TIMESTAMP = 1_745_814_599;

// ── Echidna cheat-code address ────────────────────────────────────────────────
address constant SV_HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

// ── Initial balances ──────────────────────────────────────────────────────────
uint256 constant SV_INITIAL_WETH = 10 ether;
uint256 constant SV_INITIAL_USDC = 30_000e6; // 30 000 USDC

// ── ERC20 balanceOf storage slots (for hevm.store funding) ────────────────────
// WETH on Base (OptimismMintableERC20): _balances mapping at slot 0
uint256 constant SV_WETH_BALANCE_SLOT = 0;
// USDC on Base (FiatTokenV2_2): _balanceAndBlacklistStates mapping at slot 9
uint256 constant SV_USDC_BALANCE_SLOT = 9;

// ── Uniswap V3 WETH/USDC 0.05% pool on Base ──────────────────────────────────
// tick spacing = 10; use wide range to stay in range regardless of price drift
int24 constant SV_TICK_LOWER = -887_270; // near min tick (rounded to spacing 10)
int24 constant SV_TICK_UPPER = 887_270; // near max tick
uint24 constant SV_POOL_FEE = 500; // 0.05%

// ── Fee recipient placeholder ─────────────────────────────────────────────────
address constant SV_FEE_RECIPIENT = 0x0000000000000000000000000000000000001111;
