# Trust model & how v2 addresses the v1 audit findings

## What the contract owner can do

| Power | Bound |
| --- | --- |
| Set protocol fee | Hard-capped at `MAX_FEE_BPS = 100` (1%) — enforced in the constructor and `setFee` |
| Change fee recipient | Any non-zero address |
| Pause | **New deposits only** (`lock`, `lockVesting`, `lockWithPermit`, `batchLock`, `topUp`). `claim` has no pause modifier — withdrawals can never be blocked |
| Transfer ownership | Two-step (`Ownable2Step`), so a typo can't brick admin functions |

## What the contract owner can NOT do

- Withdraw, redirect, or unlock user funds. There is no emergency-unlock flag
  (v1 had one per token), no rescue function that can reach locked balances,
  and no upgradability.
- Raise the fee above 1%, or apply a fee change retroactively (fees are taken
  only at deposit time).
- Block or delay claims.

`sweep(token)` can only move `balance - totalLocked[token]` — the surplus from
tokens mistakenly transferred straight to the vault — and only to the fee
recipient. The accounting invariant `totalLocked` is increased on deposit
(by the net amount actually received) and decreased on claim.

## v1 audit findings → v2 status

Both 2020 audit reports are archived in [audits/](audits/).

| Finding (v1) | Severity | v2 status |
| --- | --- | --- |
| Unbounded airdrop arrays could exceed block gas limit and block claims | Medium | **Removed.** The airdrop mechanism no longer exists; distribution is done off the event stream + ERC-721 snapshots |
| Owner can set fee up to 100% | Owner-privilege | **Fixed.** `MAX_FEE_BPS = 100` (1%) enforced on-chain |
| Payable `lock()` could strand accidentally-sent ETH | Low | **Fixed.** Exact `msg.value == amount` checks (`WrongMsgValue`), `receive()` reverts, and force-sent surplus is recoverable via `sweep` |
| No cap on lock duration/date | Note | **Fixed.** `end ≤ now + 100 years` (`DurationTooLong`) on lock and extend |
| `transfer()` for ETH sends (pre-Istanbul gas assumptions) | Minor (fixed in v1) | v2 uses `call{value:}` with success checks throughout |

## Additional v2 hardening

- **Reentrancy**: `nonReentrant` on every state-changing entry point +
  checks-effects-interactions ordering; ETH payouts happen after state updates.
- **Fee-on-transfer / weird ERC-20s**: balance-delta accounting on deposit;
  `SafeERC20` everywhere; position amounts are `uint128` with explicit
  overflow checks (`AmountTooLarge`).
- **Vesting math**: `claimable` is saturating — schedule changes (`extend`)
  and `split` rounding can never make a position revert on claim.
- **No token allowlist**: v1's admin-curated token registry (a liveness
  dependency and a gatekeeper) is gone entirely.
- **Solidity 0.8.28** with built-in overflow checks; custom errors; immutable-
  style minimal storage.

## Known trade-offs (read before integrating)

- **Rebasing tokens**: positive rebases accrue to the surplus (sweepable by
  the fee recipient), negative rebases can make the vault under-collateralized
  for that token. Do not lock rebasing tokens.
- **`extend` on an in-progress vesting schedule** re-stretches the line: the
  already-claimed amount stays claimed, and further vesting resumes once the
  new line crosses it. This is intentional (extend = commit to longer).
- **The v2 contract has not been audited yet.** The v1 audits do not carry
  over. Commission an audit before holding meaningful value.
