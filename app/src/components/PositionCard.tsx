import { useMemo, useState } from "react";
import type { Address } from "viem";
import {
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { lockVaultAbi } from "../abi/lockVault";
import { erc20Abi } from "../abi/erc20";
import { NATIVE_TOKEN } from "../config";
import { formatAmount, formatDate, shortAddress, timeRemaining } from "../lib/format";

export function PositionCard({
  id,
  vault,
  onChanged,
}: {
  id: bigint;
  vault: Address;
  onChanged: () => void;
}) {
  const { data: p, refetch: refetchPosition } = useReadContract({
    address: vault,
    abi: lockVaultAbi,
    functionName: "getPosition",
    args: [id],
  });
  const { data: claimableNow, refetch: refetchClaimable } = useReadContract({
    address: vault,
    abi: lockVaultAbi,
    functionName: "claimable",
    args: [id],
  });

  const isEth = p?.token === NATIVE_TOKEN;
  const { data: symbol } = useReadContract({
    address: !isEth ? p?.token : undefined,
    abi: erc20Abi,
    functionName: "symbol",
    query: { enabled: !!p && !isEth },
  });
  const { data: decimals } = useReadContract({
    address: !isEth ? p?.token : undefined,
    abi: erc20Abi,
    functionName: "decimals",
    query: { enabled: !!p && !isEth },
  });

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: confirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
    query: { enabled: !!hash },
  });
  const [handled, setHandled] = useState(false);
  if (isSuccess && !handled) {
    setHandled(true);
    void refetchPosition();
    void refetchClaimable();
    onChanged();
  }

  const view = useMemo(() => {
    if (!p) return undefined;
    const dec = isEth ? 18 : (decimals ?? 18);
    const sym = isEth ? "ETH" : (symbol ?? shortAddress(p.token));
    const now = Math.floor(Date.now() / 1000);
    const isVesting = p.start !== p.end;
    const pct =
      Number(p.end) <= now
        ? 100
        : isVesting
          ? Math.max(0, Math.min(100, ((now - Number(p.start)) / (Number(p.end) - Number(p.start))) * 100))
          : 0;
    return { dec, sym, isVesting, pct, unlocked: Number(p.end) <= now };
  }, [p, isEth, decimals, symbol]);

  if (!p || !view) return <div className="card h-48 animate-pulse" />;

  const remaining = p.amount - p.claimed;
  const canClaim = (claimableNow ?? 0n) > 0n;

  return (
    <div className="card group relative overflow-hidden p-5">
      <div className="pointer-events-none absolute -right-12 -top-12 h-32 w-32 rounded-full bg-indigo-500/10 blur-2xl transition group-hover:bg-indigo-500/20" />

      <div className="mb-4 flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xl font-bold">
              {formatAmount(remaining, view.dec)} {view.sym}
            </span>
          </div>
          <div className="mt-0.5 font-mono text-[11px] text-slate-500">
            Lock #{id.toString()} {!isEth && `· ${shortAddress(p.token)}`}
          </div>
        </div>
        <span
          className={`rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wider ${
            view.unlocked
              ? "bg-emerald-500/15 text-emerald-300"
              : view.isVesting
                ? "bg-violet-500/15 text-violet-300"
                : "bg-indigo-500/15 text-indigo-300"
          }`}
        >
          {view.unlocked ? "Unlocked" : view.isVesting ? "Vesting" : "Locked"}
        </span>
      </div>

      {/* progress */}
      <div className="mb-1.5 h-1.5 overflow-hidden rounded-full bg-white/5">
        <div
          className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-violet-400 transition-all"
          style={{ width: `${view.unlocked ? 100 : view.isVesting ? view.pct : 2}%` }}
        />
      </div>
      <div className="mb-4 flex justify-between text-[11px] text-slate-500">
        <span>
          {view.unlocked
            ? "fully unlocked"
            : `${view.isVesting ? "fully vested" : "unlocks"} in ${timeRemaining(p.end)}`}
        </span>
        <span>{formatDate(p.end)}</span>
      </div>

      {p.claimed > 0n && (
        <div className="mb-3 text-xs text-slate-400">
          Already claimed: {formatAmount(p.claimed, view.dec)} {view.sym}
        </div>
      )}

      <div className="flex gap-2">
        <button
          className="btn-primary flex-1 !py-2.5"
          disabled={!canClaim || isPending || confirming}
          onClick={() => {
            setHandled(false);
            writeContract({ address: vault, abi: lockVaultAbi, functionName: "claim", args: [id] });
          }}
        >
          {isPending || confirming
            ? "Claiming…"
            : canClaim
              ? `Claim ${formatAmount(claimableNow!, view.dec)} ${view.sym}`
              : "Nothing claimable yet"}
        </button>
      </div>
      {error && (
        <div className="mt-2 text-xs text-rose-400">
          {(error as { shortMessage?: string }).shortMessage ?? "Transaction failed"}
        </div>
      )}
    </div>
  );
}
