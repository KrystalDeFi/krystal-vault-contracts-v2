// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IWETH {
  function deposit() external payable;
  function transfer(address to, uint256 value) external returns (bool);
  function balanceOf(address) external view returns (uint256);
}

// ── Base mainnet addresses ────────────────────────────────────────────────────
address constant SV_WETH    = 0x4200000000000000000000000000000000000006;
address constant SV_USDC    = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant SV_NFPM    = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1; // Uniswap V3 on Base
address constant SV_V3UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

// ── Fork pin ──────────────────────────────────────────────────────────────────
uint256 constant SV_BLOCK_NUMBER    = 45_893_511;
uint256 constant SV_BLOCK_TIMESTAMP = 1_745_814_599;

// ── Echidna cheat-code address ────────────────────────────────────────────────
address constant SV_HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

// ── Initial balances ──────────────────────────────────────────────────────────
uint256 constant SV_INITIAL_WETH = 10 ether;
uint256 constant SV_INITIAL_USDC = 30_000e6; // 30 000 USDC

// ── Funding whale ─────────────────────────────────────────────────────────────
// Aave V3 USDC pool on Base — holds ~94M USDC at SV_BLOCK_NUMBER.
// Used with hevm.startPrank to transfer USDC into players.
// WETH is funded via hevm.deal (ETH) + WETH.deposit().
address constant SV_USDC_WHALE = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // Aave V3 USDC pool on Base

// ── Uniswap V3 WETH/USDC 0.05% pool on Base ──────────────────────────────────
// tick spacing = 10; use wide range to stay in range regardless of price drift
int24 constant SV_TICK_LOWER = -887_270; // near min tick (rounded to spacing 10)
int24 constant SV_TICK_UPPER = 887_270; // near max tick
uint24 constant SV_POOL_FEE = 500; // 0.05%

// ── Fee recipient placeholder ─────────────────────────────────────────────────
address constant SV_FEE_RECIPIENT = 0x0000000000000000000000000000000000001111;
