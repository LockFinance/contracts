export function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-4 pb-4 pt-16 text-center sm:px-6 sm:pt-24">
      <div className="mx-auto mb-6 inline-flex items-center gap-2 rounded-md border border-indigo-400/20 bg-indigo-500/10 px-4 py-1.5 font-mono text-xs font-medium text-indigo-300">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-indigo-400" />
        any ERC-20 // native ETH // no allowlists
      </div>
      <h1 className="mx-auto max-w-4xl text-balance text-3xl font-bold tracking-tight sm:text-5xl">
        <span className="text-slate-600">$&nbsp;</span>lock anything.{" "}
        <span className="bg-gradient-to-r from-indigo-400 via-violet-400 to-fuchsia-400 bg-clip-text text-transparent">
          trust nothing.
        </span>
        <span className="ml-1 inline-block h-[0.9em] w-[0.45em] translate-y-[0.1em] animate-pulse bg-indigo-400/80" />
      </h1>
      <p className="mx-auto mt-6 max-w-2xl text-pretty text-base leading-relaxed text-slate-400 sm:text-lg">
        Time-lock or vest any token and receive an NFT position. Pin payouts to your cold
        wallet, make positions untransferable — even a stolen key can&apos;t move your
        stack. No admin can touch funds or raise the fee above 1%. Enforced by the
        contract, not a promise.
      </p>
      <div className="mx-auto mt-10 grid max-w-3xl grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          ["≤1%", "hard-capped fee"],
          ["0", "admin backdoors"],
          ["1-way", "self-protection"],
          ["ERC-721", "composable positions"],
        ].map(([big, small]) => (
          <div key={small} className="card px-4 py-5">
            <div className="font-display text-2xl font-bold text-white">{big}</div>
            <div className="mt-1 font-mono text-xs text-slate-400">{small}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
