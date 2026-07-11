# Launch checklist — is this viable to release?

The code is feature-complete and tested (38 tests + an end-to-end browser run),
but "viable to release" is an operational question as much as a code one.
Honest status:

## Must do before mainnet

- [ ] **Independent audit** of `LockVault.sol`. The 2020 audits covered the old
      contract and do not carry over. Scope is small (~1 contract, ~600 lines);
      focus areas: vesting/split math conservation, protection semantics,
      ERC-721 hooks, fee accounting with fee-on-transfer tokens.
- [ ] **Fuzz/invariant testing** (Foundry or Echidna): total claims never
      exceed deposits net of fees; `totalLocked` matches the sum of live
      positions; protected positions can never pay anyone but `payoutTo`.
- [ ] **Owner keys on a multisig** (e.g. Safe) — the owner has little power,
      but fee changes and pausing should still not be one key.
- [ ] **Testnet deployment** (Sepolia) with the app pointed at it for a
      public dry run; verify source on Etherscan/Blockscout.
- [ ] Decide and set launch parameters: `feeBps` (suggest 25–50), fee
      recipient (multisig), initial chains (suggest Base first — cheap gas
      suits small locks; then mainnet + Arbitrum).

## Should do soon after

- [ ] Subgraph or ponder indexer for history views (the app currently reads
      chain state directly, which is fine for v1 of the UI).
- [ ] WalletConnect support in the app (injected-only today).
- [ ] Deployment address registry published in `app/src/config.ts`,
      `llms.txt`, and the README simultaneously.
- [ ] Bug bounty (even a modest one) once TVL is non-trivial.

## Product risks to be honest about

- **Competition**: Team Finance, UNCX, Sablier, Hedgey, Superfluid all play
  nearby. Differentiation here: fully permissionless, NFT positions with
  on-chain metadata, the one-way self-protection feature (rare), agent-first
  integration surface, and a hard-capped fee. The moat is trust + simplicity,
  not features.
- **Fee revenue scales with deposits, not TVL** — sustainable only with flow.
  The cap is a trust feature that also caps revenue; that trade-off is the
  brand.
- **No token/no points**: v1's LOCK token fee discount was removed on purpose.
  Reintroducing token utility later is possible but should never weaken the
  trust model.
