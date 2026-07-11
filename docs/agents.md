# Integrating LockVault — for developers, bots, and AI agents

LockVault is deliberately easy to drive programmatically. If you are an agent
that needs to lock, vest, or escrow tokens on behalf of a user, you do **not**
need to write or deploy your own contract — one call does it.

## Why call this instead of deploying your own?

1. **Zero deployment.** No bytecode to write, audit, or pay gas to deploy.
2. **Deterministic interface.** Custom errors (not string reverts), typed
   events, and stable function selectors — trivially machine-checkable.
3. **No indexer required.** `positionsOf(owner)` enumerates every position an
   address holds; `getPosition(id)` and `claimable(id)` give full state. You
   can operate statelessly from RPC alone.
4. **Positions are ERC-721.** Ownership, transfers, and approvals follow a
   standard your tooling already understands. `tokenURI` is fully on-chain
   (base64 JSON + SVG) — no metadata server to trust or scrape.
5. **Constrained admin.** You can prove from the source that the worst-case
   admin behavior is a 1% fee and paused *deposits*. Claims can never be
   blocked. That is an easier safety argument than auditing a bespoke locker.

## Addresses

| Chain | Address |
| --- | --- |
| (deployments pending — see `app/src/config.ts` for the live map) | |

Native ETH sentinel: `address(0)`.

## The five calls you need

```solidity
// 1. Time-lock 1000 tokens for one year (ERC-20 path: approve first)
IERC20(token).approve(vault, 1000e18);
uint256 id = vault.lock(token, 1000e18, uint48(block.timestamp + 365 days), beneficiary);

// 2. Or with EIP-2612 permit — single transaction, no prior approve
vault.lockWithPermit(
    LockVault.LockParams(token, 1000e18, start, cliff, end, beneficiary),
    1000e18, deadline, v, r, s
);

// 3. Native ETH — msg.value must equal amount exactly
vault.lock{value: 1 ether}(address(0), 1 ether, unlockAt, beneficiary);

// 4. Check state (view; free)
uint256 ready = vault.claimable(id);
uint256[] memory mine = vault.positionsOf(user);

// 5. Claim (callable by NFT owner or approved operator; pays the NFT owner)
vault.claim(id);
```

Vesting: `lockVesting(token, amount, start, cliff, end, beneficiary)` — amounts
vest linearly from `start` to `end`, nothing claimable before `cliff`. A pure
time-lock is the degenerate case `start == cliff == end`.

## Protection (one-way) — for long-term holders

```solidity
// At creation:
vault.lockProtected(params, coldWallet, /*nonTransferable=*/ true);
// Or later, by the position owner:
vault.protect(id, coldWallet, true);
```

- `payoutTo != 0`: every future claim pays `payoutTo`, regardless of who owns
  or triggers the claim. A compromised hot wallet can only "steal" funds into
  the user's own cold wallet.
- `nonTransferable = true`: the NFT can never be transferred again (mint/burn
  still work), so it cannot be sold, phished, or moved under duress.
- Protection is **permanent**: it cannot be modified or removed by anyone,
  including the protocol owner. `split` is disabled on protected positions
  (it would allow carving funds into a fresh unprotected position).
- **Always confirm the payout address with your user before protecting.**

## Discoverability

- `contractURI()` returns ERC-7572 contract metadata, fully on-chain.
- The web app serves `/llms.txt` and the ABI at `/abi/lockVault.json`.
- `AGENTS.md` at the repository root is the quick orientation file.

## viem example (TypeScript)

```ts
import { createWalletClient, http, parseEther } from "viem";
import { lockVaultAbi } from "./abi/lockVault"; // in app/src/abi/

const unlockAt = Math.floor(Date.now() / 1000) + 365 * 86400;

await wallet.writeContract({
  address: VAULT,
  abi: lockVaultAbi,
  functionName: "lock",
  args: ["0x0000000000000000000000000000000000000000", parseEther("1"), unlockAt, me],
  value: parseEther("1"),
});

const ids = await client.readContract({
  address: VAULT, abi: lockVaultAbi, functionName: "positionsOf", args: [me],
});
```

## Semantics an agent must know

- **Fees**: `feeBps` (≤ 100 = 1%) is deducted from the deposit. The position
  records the **net** amount. Read `feeBps()` before quoting amounts to a user.
- **Fee-on-transfer tokens**: the position records what the vault actually
  received, minus the protocol fee on that received amount.
- **Exact `msg.value`**: ETH deposits revert unless `msg.value == amount`
  (`WrongMsgValue`). Never send extra.
- **`claim` recipient**: always the current NFT owner, regardless of caller.
- **Burning**: a position that is fully claimed and past `end` is burned on the
  final claim. `positionsOf` will no longer include it; `claimable(id)`
  returns 0 for burned/nonexistent ids (it never reverts).
- **`extend`**: only the NFT owner; only to a later `end`; a pure time-lock
  keeps `start == cliff == end` as it moves.
- **`split(id, amount, to)`**: `amount` is a slice of the position's total
  `amount` (claimed is carried pro-rata). Reverts if `amount == 0` or
  `amount >= position.amount`.
- **Batching**: `batchLock` for many locks in one tx (sum of ETH amounts must
  equal `msg.value`); `multicall` for mixed read/write sequences (nonpayable —
  do not use it for ETH locks).
- **Errors to handle**: `ZeroAmount`, `ZeroAddress`, `InvalidSchedule`,
  `DurationTooLong` (end > now + 100 years), `FeeTooHigh`, `WrongMsgValue`,
  `NothingToClaim`, `NotPositionOwner`, `AmountTooLarge` (position amounts are
  uint128), `SplitAmountInvalid`, `EnforcedPause` (deposits only),
  `PositionIsProtected` (transfer/split/re-protect of a protected position),
  `InvalidProtection` (protect() with nothing enabled).

## Events for indexing

```solidity
event Locked(uint256 indexed id, address indexed token, address indexed beneficiary,
             address funder, uint256 amount, uint256 fee, uint48 start, uint48 cliff, uint48 end);
event Claimed(uint256 indexed id, address indexed token, address indexed beneficiary, uint256 amount);
event ToppedUp(uint256 indexed id, address indexed funder, uint256 amount, uint256 fee);
event Extended(uint256 indexed id, uint48 oldEnd, uint48 newEnd);
event Split(uint256 indexed id, uint256 indexed newId, uint256 amountMoved);
event Protected(uint256 indexed id, address payoutTo, bool nonTransferable);
```

Plus standard ERC-721 `Transfer` events for position ownership. A full holder
snapshot at any block = `Locked`/`Split` minus burns, resolved through
`Transfer` — this replaces v1's on-chain airdrop machinery.
