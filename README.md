# Lock Finance v2

**Permissionless token locking and vesting. Lock anything. Trust nothing.**

Lock Finance is a single hardened primitive for time-locking and vesting tokens:
lock any ERC-20 or native ETH until a future date — or stream it with linear
vesting and a cliff — and receive a transferable **ERC-721 position NFT** that
represents the claim.

```
contracts/LockVault.sol   the protocol (Solidity 0.8.28, OpenZeppelin 5.x)
app/                      the web app (React 19, Vite, wagmi v3, viem, Tailwind 4)
test/                     Hardhat test suite (30 tests)
docs/                     agent integration guide, trust model, legacy audits
legacy/                   the original 2020 Truffle/Solidity 0.5.15 project, kept for reference
```

## Why use this instead of building your own locker?

Every project that hand-rolls a locker ships another unaudited contract holding
other people's money. Lock Finance is designed to be the locker you *don't*
have to write, review, or trust:

- **No admin power over funds.** There is no emergency-unlock backdoor, no
  admin sweep of locked balances, and claims can never be paused. The owner's
  entire authority: a fee slider hard-capped at 1% (`MAX_FEE_BPS`), a fee
  recipient address, and pausing *new* deposits.
- **Permissionless.** Any ERC-20 and native ETH, no token allowlist, no listing
  process. Fee-on-transfer tokens are recorded at the amount actually received.
- **Positions are NFTs.** Transferable, splittable, extendable, enumerable, with
  fully on-chain metadata (JSON + SVG). Move a lock to cold storage, sell a
  vesting stream OTC, or compose it with anything that speaks ERC-721.
- **Agent- and integrator-friendly.** Deterministic custom errors, typed events,
  `positionsOf()` enumeration without an indexer, EIP-2612 `lockWithPermit`,
  `batchLock`, and `multicall`. See [docs/agents.md](docs/agents.md) for a
  copy-paste integration guide.
- **Every finding from the v1 audits is addressed** — see
  [docs/trust-model.md](docs/trust-model.md).

## Contract overview

| Function | What it does |
| --- | --- |
| `lock(token, amount, unlockAt, beneficiary)` | Pure time-lock; everything unlocks at once |
| `lockVesting(token, amount, start, cliff, end, beneficiary)` | Linear vesting with optional cliff |
| `lockWithPermit(params, value, deadline, v, r, s)` | Approve + lock in one transaction (EIP-2612) |
| `batchLock(params[])` | Many locks in one transaction (ETH + ERC-20 mixed) |
| `claim(id)` | Claim everything vested; burns the NFT when empty & expired |
| `topUp(id, amount)` | Anyone can add funds to an existing position |
| `extend(id, newEnd)` | Owner pushes the unlock further out (never earlier) |
| `split(id, amount, to)` | Carve a slice into a new position with the same schedule |
| `claimable(id)` / `vestedAmount(id, t)` / `getPosition(id)` / `positionsOf(owner)` | Views |
| `sweep(token)` | Send *surplus only* (mistaken transfers) to the fee recipient |

Native ETH is `address(0)`. Deposits take the protocol fee out of the deposited
amount; the position records the net. `msg.value` must match exactly — no
stranded ETH.

## Development

```bash
npm install
npm run compile      # hardhat compile (uses local solc-js, no binary download)
npm test             # 30-test suite
npm run deploy       # FEE_RECIPIENT=0x… FEE_BPS=50 npx hardhat run scripts/deploy.js --network <net>
```

## Web app

```bash
cd app
npm install
npm run dev          # local dev server
npm run build        # typecheck + production build
```

Point the app at a deployment by editing `app/src/config.ts` or setting
`VITE_LOCKVAULT_ADDRESS`. For local development: `npx hardhat node`, then
`npx hardhat run scripts/deploy.js --network localhost` (the default hardhat
address is pre-wired).

## v1 → v2

The original contracts (`legacy/`) required an admin-managed token allowlist,
charged tiered fees, included an admin emergency-unlock, and shipped an
airdrop distribution mechanism flagged in both audits for unbounded loops.
v2 removes the allowlist, the backdoor, and the airdrop machinery entirely;
airdrops to locked holders are better served off the `Locked`/`Claimed` event
stream and ERC-721 ownership snapshots. The two 2020 audit reports are kept in
[docs/audits/](docs/audits/). **The v2 contract has not yet been audited** —
an audit is recommended before mainnet deployment.

## License

MIT
