### Objectives:

- We can onboard big users/trading groups for Shared Vault
- The use case is limited to:
    - Vaults around big assets (gold, stables, eth, etc.)
    - Let their users deposit

### Context of the current shared-vault design:

- Current design serves a bigger need: any pairs in a fully permissionless way
- Known problem: efficiency around token swapping
- Revenue-wise: 10 Shared Vault TVL = 1 Auto-Farm TVL

### Draft & Ideas

[Please add an expandable for yourself]

- Jarvis
    
    **Methodology**
    
    - Vault owner will be the **PRIORITY-USER**, not the vault participants
    - The platform tries to give the vault owner the flexibility and efficiency of managing a vault, while vault participants need to be clear on the risk
    
    **Details**
    
    - Standard Guard:
        - Vault supports only a list of Whitelisted Assets (Stables, Gold, Native Tokens based on each chain, and to be added more based on requests)
        - Have liquidity pools (≥ $100k value)
        - Or make this a configurable option if no more effort. we show the Basic Guard enabled/disabled in the frontend.
    - Remove the config for Range Config, TVL config, Whitelisted Pools
    - Remove the need for principal token?
    
    **Technical:**
    
    - Probably an oracle is needed
    - Swap-Router is needed for efficiency
    - Supported chain: should limit to popular chain only (Ethereum, Base, BNB)
    
    **Non-Tech:**
    
    - A revised Terms needed & shown clearly for Deposit action
    
    **Migration:**
    
    - Old-shared vault should still work, but users can’t create more
    - New flow for shared vault creation
    
- NguyenNK
    - Do we need multiple assets vault? Is single-asset vault sufficient?
    - We would need a new set of contracts, we also need share management, more complex than AutoFarm/PrivateVault so Audit is also needed

- Steve
    
    **Hypothesis:** 
    
    - There is a market for community vaults (size???).
    - Shared Vault is uniquely differentiated, with no equivalent on other platforms, and it gives vault owners a monetization lever through customizable commission fees.
    
    **Reality**
    
    - Adoption remains limited: only **8 vaults** have reached **$20K+ TVL (72 participants** in total)
    
    **Key pain points**
    
    - Setup is complex: requires many configuration decisions and understanding their impacts
        - 7/8 top TVL vaults have HIGH Risk level, even though their strategies focus on high liquid pools and strong tokens.
        
        ![Screenshot 2026-03-18 at 13.48.06.png](attachment:8e09b335-78ae-4bb8-842d-ef4d44bf6f1f:Screenshot_2026-03-18_at_13.48.06.png)
        
    - Can’t change vault settings: After a vault has been running for some time, owners often need to adjust settings to reflect performance or strategy changes. But the current design enforces fixed settings, so users cannot update a live vault. Their only option is to create a new vault, which creates migration friction and hurts conversion.
    - High slippage: Direct pool swaps create significant slippage and price impact, especially for large LP positions (common in community vaults). This makes execution less efficient and can materially reduce user returns.
    - Shared logic worsens execution: one position with high slippage needs can raise slippage for all positions.
        - When participants deposit and withdraw
    - Automation must be highly reliable: users expect accurate and timely execution, especially for auto-exit.
        - An auto-exit failure can make a big loss because vaults often hold large position sizes.
    
    **Suggestion improvements(by orders)**
    
    - Simplify vault setup for onboarding
        - Reduce setup to only 2 options:
            - **Community Vaults**
                - Flexible ranges
                - TVL ≥ 200K
            - **Custom Vaults**
                - Keep the current advanced setup
    - Allow vault setting change requests
        - Let vault owners request updates to settings such as range or TVL, with Krystal approval via multisig
    - Add automation notifications
        - Notify users of important automation events, especially failures or missed actions
    - Improve swap routing
    - Improve shared calculation
- Long
    
    Another look at current shared vault weeknesses:
    
    1. Too many restrictions: Range Config, TVL Config, Whitelisted Pools, TWAP
        - Actually, I think these restrictions can be removed on KYC/connected X because shared vault can be reputation based. Or just keep it as it doesn’t not to complex to understand
        - The key pain point may be the TWAP, so it makes transaction more easy to fail/must wait for enable TWAP/…
    2. Swap efficiency
        - Swap aggregator is mandatory as current slippage of pool swap is unacceptable
    3. Shares (principal token)
        - As using of swap aggregator (which built from our API and can’t be along with on-chain right shares calculation), how about an off-chain shares management → deposit/withdraw built from API
            - Keep some restricted principal token on-chain is much easier for user as I think no one want to manage small assets partially when exiting. Also, to prevent vault owner exit to their token
            - Flow: When user deposit, we calculate vault LP state, then swapped to idle tokens + built zap-ins to these positions with proportional ratio, sum up value after add, then calculate shares. The same with withdrawal
    4. Vault abilities
        - Claim and keep fees without converting them to target token
        - …
    
    Risks:
    
    - If follow this design, basically, the vault is more efficient but fully depends on our API → if server downs, withdraw using SC using pool swap and keep idle tokens, can’t deposit, manage LP using pool swap
    - Data syncing, if LP recently changed, or someone deposit before but data haven’t updated yet, shares can be calculated wrongly → need idempotency handling for data syncing and API build transaction to vault
    
    Design
    
    ![image.png](attachment:038a577d-e62e-45bf-a45d-e8ade83674ff:image.png)
    

### [TBD] Final Design

#### Objectives

- 20% team effort max
- User-wise: Serving **VAULT OWNER**, focus on the ability to share back to their followers
- Business-wise: minimal & 1 time development effort, focusing on BD and partnership to acquire $5M TVL

#### Key Requirements

- **1 Pair for 1 Vault (e.g XAU - USDT, any pools)**
    - Vault can have: XAU, USDT, XAU-USDT LP
    - **Option 2**:
        - 2 pairs: .e.g XAU - USDT, USDT - USDC (could be multiple pools)
        - XAU / USDT / USDC / LPs
- **Sharable**
- Auto-Compound
- Swap Router

Pending: discuss timeline March 30, 2026
