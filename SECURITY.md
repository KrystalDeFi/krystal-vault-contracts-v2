# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Krystal Vault contracts, please report it responsibly through one of the following channels:

- **GitHub:** Use the [Report a vulnerability](../../security/advisories/new) button on this repository's Security tab (requires GitHub account)

Do **not** open a public GitHub issue for security vulnerabilities.

## Scope

### In Scope

- All Solidity smart contracts in this repository (public vaults, private vaults, shared vaults)
- Deployments on **Ethereum, Arbitrum, Base, BSC, Polygon and Robinhood**
- Vulnerabilities in how Krystal contracts integrate with third-party protocols (Uniswap, PancakeSwap, Aerodrome, SushiSwap, etc.)
- Access control, governance, and upgrade mechanism vulnerabilities

### Out of Scope

- Bugs in third-party protocols themselves (report these to the respective protocol's security program)
- Off-chain infrastructure, web applications, APIs, and backend services
- Deployments on chains not listed above
- Issues already disclosed in public audit reports or known issues acknowledged by the team
- Findings from automated scanners without a demonstrated impact
- Theoretical attacks without a realistic exploit scenario
- Attacks that require a trusted role to act maliciously, as defined in the [Trust Model](#trust-model) below

## Trust Model

Reports are assessed against the following trust assumptions. Issues that depend on a trusted party abusing its role are considered accepted risks of the design, not security vulnerabilities. We may still fix them as logic improvements.

### Trusted roles

- **Krystal-operated roles:** factory and config manager owners (governance), the vault `operator`, the whitelisted swap-data signers, and whitelisted automation callers.
- **Shared vault owner:** depositors in a shared vault trust its vault owner. The owner manages the vault's funds on behalf of depositors, including choosing positions, pools, and when to enter or exit them. Actions by the vault owner, or by admins and automation the owner authorizes, against that vault's own depositors are out of scope.

### Untrusted parties

- Depositors and shareholders
- Any external account or contract, including other vault owners acting against vaults they do not own

In-scope examples: a depositor or outsider taking funds from other depositors, stealing platform or vault-owner fees, or freezing deposits and withdrawals; and a vault owner affecting other vaults, Krystal's platform fees, or protocol-level contracts.

## Severity and Rewards

We offer discretionary rewards for valid vulnerability reports based on severity:

| Severity | Reward Range |
|----------|-------------|
| **Critical** — direct loss of funds, permanent freezing of funds, or protocol insolvency | $2,000 – $8,000 |
| **High** — theft of unclaimed yield, temporary freezing of funds, or manipulation of contract state with limited impact | Case-by-case |
| **Medium / Low / Informational** | Acknowledgment only |

Reward amounts are determined at our sole discretion based on the severity, quality of the report, and potential impact. We prioritize critical and high severity vulnerabilities.

A valid report must include:

- A clear description of the vulnerability
- Step-by-step reproduction instructions or a proof of concept
- The affected contract(s) and chain(s)
- An assessment of the potential impact

## Response Process

- We will acknowledge receipt of your report within **72 hours**
- If your report duplicates a previously identified issue, we will prioritize the first report for a reward.
- Reward decisions are final and at the discretion of the Krystal Security Team

## Disclosure Policy

To protect our users, we ask that you:

- Allow us **90 days** from the initial report before making any public disclosure
- Make a good-faith effort to avoid privacy violations, data destruction, and service disruption during your research
- Only interact with accounts you own or with explicit permission from the account holder
- Not exploit a vulnerability beyond what is necessary to demonstrate it

## Safe Harbor

Krystal will not pursue legal action against security researchers who:

- Act in good faith and in accordance with this policy
- Avoid causing harm to Krystal users, including disruption of service, data loss, or unauthorized access to user accounts
- Do not publicly disclose vulnerability details before the agreed-upon disclosure timeline
- Report vulnerabilities through the channels specified in this policy

We consider security research conducted in compliance with this policy to be authorized and will not initiate legal action for accidental, good-faith violations of this policy.

> Krystal reserves the right to modify, suspend, or terminate this security program and its rewards at any time, at its sole discretion, with or without notice. All decisions regarding eligibility, severity classification, and reward amounts are final.

## Contact

**Krystal Team**
[support@krystal.app](mailto:support@krystal.app)
