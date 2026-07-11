import { useAccount, useChainId, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { shortAddress } from "../lib/format";

export function Header() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const { chains, switchChain } = useSwitchChain();

  return (
    <header className="sticky top-0 z-20 border-b border-white/5 bg-slate-950/70 backdrop-blur-md">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 sm:px-6">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-indigo-400/40 bg-indigo-500/10 font-mono text-sm font-bold text-indigo-300 shadow-lg shadow-indigo-500/20">
            &gt;_
          </div>
          <div className="font-mono">
            <div className="text-sm font-bold tracking-tight">
              lock<span className="text-indigo-400">.finance</span>
            </div>
            <div className="text-[10px] uppercase tracking-[0.25em] text-slate-500">
              v2 // permissionless
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {isConnected && (
            <select
              className="hidden rounded-xl border border-white/10 bg-slate-900/70 px-3 py-2 text-xs text-slate-300 outline-none sm:block"
              value={chainId}
              onChange={(e) => switchChain({ chainId: Number(e.target.value) as never })}
            >
              {chains.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          )}
          {isConnected && address ? (
            <button className="btn-ghost font-mono text-xs" onClick={() => disconnect()}>
              <span className="h-2 w-2 rounded-full bg-emerald-400" />
              {shortAddress(address)}
            </button>
          ) : (
            <button
              className="btn-primary"
              disabled={isPending}
              onClick={() => connect({ connector: connectors[0] })}
            >
              {isPending ? "Connecting…" : "Connect wallet"}
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
