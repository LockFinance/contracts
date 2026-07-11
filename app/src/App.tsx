import { useState } from "react";
import { useAccount } from "wagmi";
import { Header } from "./components/Header";
import { Hero } from "./components/Hero";
import { LockForm } from "./components/LockForm";
import { Positions } from "./components/Positions";
import { WhySection } from "./components/WhySection";

type Tab = "lock" | "positions";

export default function App() {
  const { isConnected } = useAccount();
  const [tab, setTab] = useState<Tab>("lock");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="min-h-screen">
      <Header />
      <Hero />

      <main className="mx-auto max-w-2xl px-4 py-12 sm:px-6">
        {isConnected ? (
          <>
            <div className="mb-6 flex justify-center gap-1 rounded-xl bg-slate-900/80 p-1">
              {(
                [
                  ["lock", "＋ New lock"],
                  ["positions", "My positions"],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  onClick={() => setTab(value)}
                  className={`flex-1 rounded-lg px-4 py-2.5 text-sm font-medium transition ${
                    tab === value
                      ? "bg-indigo-500/20 text-white ring-1 ring-indigo-400/40"
                      : "text-slate-400 hover:bg-white/5 hover:text-slate-200"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            {tab === "lock" ? (
              <LockForm
                onLocked={() => {
                  setRefreshKey((k) => k + 1);
                  setTab("positions");
                }}
              />
            ) : (
              <Positions refreshKey={refreshKey} />
            )}
          </>
        ) : (
          <div className="card px-6 py-16 text-center">
            <div className="mb-3 text-4xl">👛</div>
            <p className="text-sm text-slate-400">
              Connect a wallet to create locks and manage your positions.
            </p>
          </div>
        )}
      </main>

      <WhySection />

      <footer className="border-t border-white/5 py-10 text-center text-xs text-slate-600">
        Lock Finance v2 · open source · no admin can touch your funds —{" "}
        <a
          className="text-slate-400 underline decoration-dotted hover:text-indigo-300"
          href="https://github.com/LockFinance/contracts"
          target="_blank"
          rel="noreferrer"
        >
          read the contract
        </a>
      </footer>
    </div>
  );
}
