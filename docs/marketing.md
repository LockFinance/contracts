# Lock Finance v2 — launch marketing plan

## The one-sentence pitch

**Lock anything. Trust nothing.** — a token locker where even the admin can't
touch your funds, and even a *stolen key* can't move your stack.

## What's actually marketable here

Most lockers market "we hold your tokens." That's table stakes. We have three
hooks that are genuinely uncommon, in order of viral potential:

1. **Hodl protection** (the hero). "If your wallet gets phished tomorrow, the
   attacker can claim your tokens — into *your* cold wallet." Nobody else
   leads with this. Wallet-drainer fear is the most relatable pain in crypto
   right now, and every drainer headline is free distribution for us.
2. **Provable trustlessness** (the substance). The admin's total power: a fee
   slider capped at 1% and pausing *new* deposits. No emergency unlock, no
   upgrade key, claims can never be paused. This is checkable in ~600 lines.
3. **Agent-native** (the wedge). AGENTS.md, llms.txt, on-chain contractURI,
   no-indexer views. As AI agents start executing DeFi tasks, being the locker
   an agent *finds and integrates in one session* is a real distribution
   channel no incumbent is serving.

## Audiences → message → channel

| Audience | Message | Where |
| --- | --- | --- |
| Long-term holders / self-custody maxis | "Phish-proof your bags. One transaction." | X/Twitter, Farcaster, r/ethereum, r/Bitcoin-adjacent hodl culture, hardware-wallet communities (Ledger/Trezor forums) |
| Projects (team vesting, investor cliffs, LP locks) | "Vesting your lawyers and your community can both verify. No allowlist, no listing fee." | DeFi founder Telegram groups, launchpad partnerships, "how to vest your team tokens" SEO content |
| Agent/tool builders | "The locker your agent already knows how to use." | MCP/agent tool registries, ETHGlobal hackathon bounties, dev X, llms.txt directories |

## Launch sequence (gated by the launch checklist)

**Phase 0 — pre-audit (now).** Ship the story before the product: a thread
series on *why lockers are trust bombs* (v1 audit findings of the industry:
emergency-unlock backdoors, unlimited fees, upgradeable custody). Build the
enemy; the enemy is "trust me bro" lockers. Collect a waitlist.

**Phase 1 — audit + testnet (weeks 1–4).** Publish the audit publicly the day
it lands, including anything embarrassing — transparency IS the campaign.
Sepolia "lock rehearsal": anyone who creates a testnet lock gets on the
launch-day allowlist for a fee-free window.

**Phase 2 — mainnet launch (day 0–14).**
- Launch offer: **0 bps fee for the first 30 days** (set feeBps=0, raise to
  25–50 later — the cap being 1% makes "we will raise it later" a non-scary
  sentence, say it out loud).
- Founder locks the project's own treasury/team allocation as **Lock #1–#N,
  protected, multi-year** — on camera, linked from the homepage. Eat your own
  cooking; make Lock #1 a monument.
- The NFT SVG cards are the share unit: "I locked. 🔒 #ProofOfHodl" quote-tweet
  chain. Every lock mints its own marketing asset — lean into it with a
  /lock/:id share page and OG image later.

**Phase 3 — agent & integrator push (weeks 2–8).** Ship an MCP server wrapping
the five calls; submit to agent tool directories; $2–5k ETHGlobal bounty for
"best thing built on a LockVault position" (positions are ERC-721 — lending
against locks, lock marketplaces, DAO vote-weight from locked balances).
Publish a Dune dashboard (TVL, locks, protected %) — public numbers are
content.

## Content backlog (ready to draft)

- Thread: "Your token locker has an emergency unlock button. Ours doesn't. A
  thread on reading the fine print of custody 🧵"
- Thread: "We made a lock that protects you FROM YOURSELF. Here's how a
  drained wallet loses nothing:"
- Blog: "Why we removed our own token from our fee model"
- Blog/SEO: "How to vest team tokens (2026 guide)", "Liquidity lock vs vesting
  vs escrow"
- Demo (60s screen recording): phished-wallet simulation — attacker claims,
  cold wallet receives. This is *the* clip.
- Comparison page: Lock vs Team Finance vs UNCX vs Sablier vs Hedgey — one
  row per admin power, ours mostly "—".

## Taglines (pick a lane, use everywhere)

- `lock anything. trust nothing.` (current, keep)
- `the locker with no back door.`
- `a stolen key can't move your stack.`
- `hodl, enforced.`

## What we do NOT do

No paid KOL shilling (it poisons the trust positioning — our entire brand is
"verify, don't trust"), no token launch promises, no APY theater, no
"partnership" announcements that are just mutual retweets.

## Measurement

North star: **value locked by wallets we don't know** (organic TVL).
Supporting: locks created/week, % protected locks (feature adoption), unique
claimers, external contracts/agents calling the vault (integration count),
share-card impressions. Kill criteria for channels: anything not producing
locks in 4 weeks gets cut.

## Budget shape (lean)

Audit ($15–40k) is the biggest and most marketable line item. Then: hackathon
bounties ($5k), Dune/analytics (free), demo production (in-house), everything
else is founder-led content. This product markets on credibility, not spend.
