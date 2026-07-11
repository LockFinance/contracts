export function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-4 pb-4 pt-16 text-center sm:px-6 sm:pt-24">
      <div className="mx-auto mb-6 inline-flex items-center gap-2 rounded-full border border-indigo-400/20 bg-indigo-500/10 px-4 py-1.5 text-xs font-medium text-indigo-300">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-indigo-400" />
        Any ERC-20 · Native ETH · No allowlists
      </div>
      <h1 className="mx-auto max-w-3xl text-balance text-4xl font-extrabold tracking-tight sm:text-6xl">
        Lock anything.{" "}
        <span className="bg-gradient-to-r from-indigo-400 via-violet-400 to-fuchsia-400 bg-clip-text text-transparent">
          Trust nothing.
        </span>
      </h1>
      <p className="mx-auto mt-6 max-w-2xl text-pretty text-base leading-relaxed text-slate-400 sm:text-lg">
        Time-lock or vest any token and receive a transferable NFT position. No admin can
        touch your funds, pause your claim, or raise the fee above 1% — it&apos;s enforced
        by the contract, not a promise.
      </p>
      <div className="mx-auto mt-10 grid max-w-3xl grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          ["≤ 1%", "hard-capped fee"],
          ["0", "admin backdoors"],
          ["ERC-721", "composable positions"],
          ["100%", "on-chain metadata"],
        ].map(([big, small]) => (
          <div key={small} className="card px-4 py-5">
            <div className="text-2xl font-bold text-white">{big}</div>
            <div className="mt-1 text-xs text-slate-400">{small}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
