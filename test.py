# import matplotlib.pyplot as plt

# Simulating a simple Uniswap v2-like AMM (x * y = k)
# Starting pool: 100 ETH : 100,000 MEME

initial_eth = 100
initial_meme = 100_000
k = initial_eth * initial_meme

swap_fee = 0.003

def get_meme_out_for_eth_in(eth_in, eth_reserve, meme_reserve, fee=swap_fee):
    eth_in_after_fee = eth_in * (1 - fee)
    new_eth_reserve = eth_reserve + eth_in_after_fee
    new_meme_reserve = k / new_eth_reserve
    meme_out = meme_reserve - new_meme_reserve
    return meme_out

def get_eth_out_for_meme_in(meme_in, eth_reserve, meme_reserve, fee=swap_fee):
    meme_in_after_fee = meme_in * (1 - fee)
    new_meme_reserve = meme_reserve + meme_in_after_fee
    new_eth_reserve = k / new_meme_reserve
    eth_out = eth_reserve - new_eth_reserve
    return eth_out


# Attacker front-runs: dumps 1,000 MEME
victim_eth_in = 1


for attacker_eth_in in range(100, 500, 100):
    print("+++ attacker_eth_in: ", attacker_eth_in)

    # Simulate the sandwich attack:
    eth_reserve = initial_eth
    meme_reserve = initial_meme

    # (1) Attacker front-runs: swap ETH -> MEME
    meme_received_from_frontrun = get_meme_out_for_eth_in(attacker_eth_in, eth_reserve, meme_reserve)
    eth_reserve += attacker_eth_in * (1 - swap_fee)
    meme_reserve -= meme_received_from_frontrun
    print("(1) meme_received_from_frontrun: ", meme_received_from_frontrun)

    # (2) Victim swaps 1 ETH for MEME at new price
    
    meme_received_by_victim = get_meme_out_for_eth_in(victim_eth_in, eth_reserve, meme_reserve)
    
    print("(2) meme_received_by_victim: ", meme_received_by_victim)

    eth_reserve += victim_eth_in * (1 - swap_fee)
    meme_reserve -= meme_received_by_victim

    # (3) Attacker back-runs: buy back MEME -> ETH
    eth_gained_from_sell = get_eth_out_for_meme_in(meme_received_from_frontrun, eth_reserve, meme_reserve)        
    print("(3) eth_gained_from_sell: ", eth_gained_from_sell)

    # Compare: attacker started with 1,000 MEME, ended with this much
    attacker_profit_eth = eth_gained_from_sell - attacker_eth_in

    print("attacker_profit_eth: ", attacker_profit_eth)
    print("")

