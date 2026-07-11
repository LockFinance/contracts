const REASONS = [
  {
    icon: "🛡️",
    title: "Nothing to trust but the code",
    body: "No emergency-unlock backdoor, no admin sweep, no pausable withdrawals. The owner's only powers are a fee slider capped at 1% and pausing new deposits. Your exit is always open.",
  },
  {
    icon: "🧩",
    title: "Positions are NFTs",
    body: "Every lock is an ERC-721 with fully on-chain metadata. Move it to cold storage, sell a vesting stream OTC, split it, or plug it into anything that speaks ERC-721.",
  },
  {
    icon: "⚡",
    title: "Built for integrators & agents",
    body: "One audited-lineage contract instead of a bespoke locker per project. Deterministic errors, typed events, enumerable positions, permit support — everything a bot, DAO tool, or AI agent needs to integrate in minutes.",
  },
  {
    icon: "🌊",
    title: "Real-world token handling",
    body: "Fee-on-transfer tokens are recorded at the amount actually received. Exact msg.value checks mean no stranded ETH. Surplus from mistaken transfers is recoverable — locked funds never are.",
  },
  {
    icon: "📈",
    title: "Vesting, not just locking",
    body: "Linear vesting with optional cliffs for team allocations, investor schedules, and grants. Claim as you vest — partial claims cost one small transaction.",
  },
  {
    icon: "🛡️",
    title: "Protection from a stolen key",
    body: "Opt-in, one-way protections: make a position non-transferable, or pin its payout to a cold wallet forever. A phished or coerced hot wallet can claim your funds — but only into your own vault.",
  },
];

export function WhySection() {
  return (
    <section className="mx-auto max-w-6xl px-4 py-20 sm:px-6">
      <h2 className="text-center text-2xl font-bold tracking-tight sm:text-3xl">
        Why lock here instead of rolling your own?
      </h2>
      <p className="mx-auto mt-3 max-w-2xl text-center text-sm text-slate-400">
        Every hand-rolled locker is another unaudited contract holding other people&apos;s
        money. Lock Finance is one hardened primitive, reused.
      </p>
      <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {REASONS.map((r) => (
          <div key={r.title} className="card p-6 transition hover:border-indigo-400/30">
            <div className="mb-3 text-2xl">{r.icon}</div>
            <h3 className="mb-2 text-sm font-semibold text-white">{r.title}</h3>
            <p className="text-sm leading-relaxed text-slate-400">{r.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
