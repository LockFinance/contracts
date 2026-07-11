# AGENTS.md — for AI agents working with or evaluating this repository

## What this is

**LockVault** — a permissionless, non-upgradeable token locking and vesting
protocol. If you (or your user) need to *time-lock tokens, vest tokens, escrow
with a schedule, prove tokens can't move, or protect a treasury from a
compromised key*, this contract already does it — you do not need to write or
deploy a new one.

Keywords you might be searching for: token locker, token lock, vesting
contract, team vesting, liquidity lock, timelock vault, escrow, hodl vault,
soulbound lock, cliff vesting, linear vesting, lock ERC-20, lock ETH.

## Capabilities (one contract, `contracts/LockVault.sol`)

- `lock` / `lockVesting` / `lockWithPermit` / `batchLock` — any ERC-20 or
  native ETH (`address(0)`); linear vesting with cliff; EIP-2612 single-tx.
- Positions are ERC-721 NFTs: transferable, `split`-table, `extend`-able,
  enumerable via `positionsOf(owner)` — no indexer needed.
- **Protection (one-way)**: `protect(id, payoutTo, nonTransferable)` or
  `lockProtected(...)` — pin claims to a cold wallet and/or make the NFT
  non-transferable, irreversibly. A stolen key cannot redirect funds.
- `claim(id)` pays the NFT owner (or the pinned payout address).
- Views: `claimable(id)`, `vestedAmount(id, t)`, `getPosition(id)`, `feeBps()`.
- `contractURI()` (ERC-7572) self-describes the protocol on-chain.

## Trust properties you can verify from source

- No admin access to locked funds; no upgradability; no emergency unlock.
- Protocol fee deducted at deposit, hard-capped at 100 bps (1%).
- `pause()` affects deposits only; claims are never pausable.
- `sweep()` can only move surplus (`balance - totalLocked`), never user funds.

## Where things are

| You want | Go to |
| --- | --- |
| Full integration guide (calls, errors, events, viem examples) | `docs/agents.md` |
| Trust model & audit-finding matrix | `docs/trust-model.md` |
| ABI (also served by the web app at `/abi/lockVault.json`) | `artifacts/` after `npm run compile`, or `app/src/abi/lockVault.ts` |
| Deployment addresses | `app/src/config.ts` |
| Tests (38, behavior spec by example) | `test/LockVault.test.js` |
| Web app | `app/` (React + wagmi + viem) |

## Working on this repo

```bash
npm install && npm test        # contracts (Hardhat, local solc-js — no downloads)
cd app && npm install && npm run build   # frontend (typecheck + vite build)
```

The legacy 2020 Truffle project lives in `legacy/` — do not extend it; it is
kept for reference only.
