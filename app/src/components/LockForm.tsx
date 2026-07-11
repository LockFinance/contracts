import { useMemo, useState } from "react";
import { isAddress, parseUnits, type Address } from "viem";
import {
  useAccount,
  useChainId,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { lockVaultAbi } from "../abi/lockVault";
import { erc20Abi } from "../abi/erc20";
import { lockVaultAddress, NATIVE_TOKEN } from "../config";
import { defaultUnlockInput, inputToUnix } from "../lib/format";

type Mode = "timelock" | "vesting";

export function LockForm({ onLocked }: { onLocked: () => void }) {
  const { address } = useAccount();
  const chainId = useChainId();
  const vault = lockVaultAddress(chainId);

  const [mode, setMode] = useState<Mode>("timelock");
  const [useEth, setUseEth] = useState(false);
  const [tokenInput, setTokenInput] = useState("");
  const [amount, setAmount] = useState("");
  const [unlockAt, setUnlockAt] = useState(defaultUnlockInput(30));
  const [cliffAt, setCliffAt] = useState(defaultUnlockInput(90));
  const [endAt, setEndAt] = useState(defaultUnlockInput(365));
  const [beneficiary, setBeneficiary] = useState("");
  const [nonTransferable, setNonTransferable] = useState(false);
  const [payoutTo, setPayoutTo] = useState("");

  const token: Address | undefined = useEth
    ? NATIVE_TOKEN
    : isAddress(tokenInput)
      ? tokenInput
      : undefined;
  const isErc20 = token !== undefined && token !== NATIVE_TOKEN;

  const { data: decimals } = useReadContract({
    address: isErc20 ? token : undefined,
    abi: erc20Abi,
    functionName: "decimals",
    query: { enabled: isErc20 },
  });
  const { data: symbol } = useReadContract({
    address: isErc20 ? token : undefined,
    abi: erc20Abi,
    functionName: "symbol",
    query: { enabled: isErc20 },
  });

  const tokenDecimals = useEth ? 18 : decimals;
  const parsedAmount = useMemo(() => {
    if (!amount || tokenDecimals === undefined) return undefined;
    try {
      const v = parseUnits(amount, tokenDecimals);
      return v > 0n ? v : undefined;
    } catch {
      return undefined;
    }
  }, [amount, tokenDecimals]);

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: isErc20 ? token : undefined,
    abi: erc20Abi,
    functionName: "allowance",
    args: address && vault ? [address, vault] : undefined,
    query: { enabled: isErc20 && !!address && !!vault },
  });

  const needsApproval =
    isErc20 && parsedAmount !== undefined && (allowance === undefined || allowance < parsedAmount);

  const {
    writeContract: writeApprove,
    data: approveHash,
    isPending: approving,
    error: approveError,
  } = useWriteContract();
  const { isLoading: approveConfirming, isSuccess: approved } = useWaitForTransactionReceipt({
    hash: approveHash,
    query: { enabled: !!approveHash },
  });
  if (approved && needsApproval) void refetchAllowance();

  const {
    writeContract: writeLock,
    data: lockHash,
    isPending: locking,
    error: lockError,
    reset: resetLock,
  } = useWriteContract();
  const { isLoading: lockConfirming, isSuccess: lockDone } = useWaitForTransactionReceipt({
    hash: lockHash,
    query: { enabled: !!lockHash },
  });
  if (lockDone) {
    onLocked();
    resetLock();
    setAmount("");
  }

  const receiver = (beneficiary && isAddress(beneficiary) ? beneficiary : address) as
    | Address
    | undefined;

  const schedule = useMemo(() => {
    const now = Math.floor(Date.now() / 1000);
    if (mode === "timelock") {
      const end = inputToUnix(unlockAt);
      return end > now ? { start: end, cliff: end, end } : undefined;
    }
    const start = now;
    const cliff = inputToUnix(cliffAt);
    const end = inputToUnix(endAt);
    return start <= cliff && cliff <= end && end > now ? { start, cliff, end } : undefined;
  }, [mode, unlockAt, cliffAt, endAt]);

  const payoutValid = payoutTo === "" || isAddress(payoutTo);
  const wantsProtection = nonTransferable || (payoutTo !== "" && isAddress(payoutTo));

  const ready =
    !!vault &&
    !!token &&
    !!parsedAmount &&
    !!receiver &&
    !!schedule &&
    !needsApproval &&
    payoutValid;

  function submit() {
    if (!vault || !token || !parsedAmount || !receiver || !schedule) return;
    const value = useEth ? parsedAmount : 0n;

    if (wantsProtection) {
      writeLock({
        address: vault,
        abi: lockVaultAbi,
        functionName: "lockProtected",
        args: [
          {
            token,
            amount: parsedAmount,
            start: schedule.start,
            cliff: schedule.cliff,
            end: schedule.end,
            beneficiary: receiver,
          },
          isAddress(payoutTo) ? payoutTo : ("0x0000000000000000000000000000000000000000" as Address),
          nonTransferable,
        ],
        value,
      });
    } else if (mode === "timelock") {
      writeLock({
        address: vault,
        abi: lockVaultAbi,
        functionName: "lock",
        args: [token, parsedAmount, schedule.end, receiver],
        value,
      });
    } else {
      writeLock({
        address: vault,
        abi: lockVaultAbi,
        functionName: "lockVesting",
        args: [token, parsedAmount, schedule.start, schedule.cliff, schedule.end, receiver],
        value,
      });
    }
  }

  const error = approveError ?? lockError;

  if (!vault) {
    return (
      <div className="card px-6 py-8 text-center text-sm text-slate-400">
        LockVault isn&apos;t deployed on this network yet — switch networks, or set{" "}
        <code className="rounded bg-white/10 px-1.5 py-0.5 font-mono text-xs">
          VITE_LOCKVAULT_ADDRESS
        </code>{" "}
        for a custom deployment.
      </div>
    );
  }

  return (
    <div className="card p-6 sm:p-8">
      {/* mode switch */}
      <div className="mb-6 grid grid-cols-2 gap-1 rounded-xl bg-slate-900/80 p-1">
        {(
          [
            ["timelock", "Time-lock", "everything unlocks at once"],
            ["vesting", "Linear vesting", "streams over time, optional cliff"],
          ] as const
        ).map(([value, title, sub]) => (
          <button
            key={value}
            onClick={() => setMode(value)}
            className={`rounded-lg px-4 py-3 text-left transition ${
              mode === value ? "bg-indigo-500/20 ring-1 ring-indigo-400/40" : "hover:bg-white/5"
            }`}
          >
            <div className="text-sm font-semibold">{title}</div>
            <div className="text-xs text-slate-400">{sub}</div>
          </button>
        ))}
      </div>

      {/* asset */}
      <div className="mb-4">
        <span className="label">Asset</span>
        <div className="flex gap-2">
          <button
            className={`btn-ghost shrink-0 ${useEth ? "border-indigo-400/50 bg-indigo-500/15 text-indigo-200" : ""}`}
            onClick={() => setUseEth(!useEth)}
          >
            Ξ ETH
          </button>
          <input
            className="input font-mono"
            placeholder="ERC-20 token address (0x…)"
            value={useEth ? "" : tokenInput}
            disabled={useEth}
            onChange={(e) => setTokenInput(e.target.value.trim())}
          />
        </div>
        {isErc20 && symbol && (
          <div className="mt-1.5 text-xs text-emerald-400">
            ✓ {symbol} · {decimals} decimals
          </div>
        )}
        {!useEth && tokenInput && !isAddress(tokenInput) && (
          <div className="mt-1.5 text-xs text-rose-400">Not a valid address</div>
        )}
      </div>

      {/* amount */}
      <div className="mb-4">
        <span className="label">Amount</span>
        <input
          className="input"
          placeholder="0.0"
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value.trim())}
        />
      </div>

      {/* schedule */}
      {mode === "timelock" ? (
        <div className="mb-4">
          <span className="label">Unlocks at</span>
          <input
            type="datetime-local"
            className="input"
            value={unlockAt}
            onChange={(e) => setUnlockAt(e.target.value)}
          />
          <div className="mt-2 flex gap-2">
            {[
              ["1 month", 30],
              ["6 months", 182],
              ["1 year", 365],
              ["4 years", 1461],
            ].map(([label, days]) => (
              <button
                key={label}
                className="rounded-lg border border-white/10 px-2.5 py-1 text-xs text-slate-400 transition hover:border-indigo-400/40 hover:text-indigo-300"
                onClick={() => setUnlockAt(defaultUnlockInput(days as number))}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      ) : (
        <div className="mb-4 grid gap-4 sm:grid-cols-2">
          <div>
            <span className="label">Cliff (nothing before)</span>
            <input
              type="datetime-local"
              className="input"
              value={cliffAt}
              onChange={(e) => setCliffAt(e.target.value)}
            />
          </div>
          <div>
            <span className="label">Fully vested at</span>
            <input
              type="datetime-local"
              className="input"
              value={endAt}
              onChange={(e) => setEndAt(e.target.value)}
            />
          </div>
        </div>
      )}

      {/* beneficiary */}
      <div className="mb-4">
        <span className="label">Beneficiary (optional — defaults to you)</span>
        <input
          className="input font-mono"
          placeholder={address ?? "0x…"}
          value={beneficiary}
          onChange={(e) => setBeneficiary(e.target.value.trim())}
        />
      </div>

      {/* protection */}
      <div className="mb-6 rounded-xl border border-amber-400/15 bg-amber-500/[0.04] p-4">
        <div className="mb-3 flex items-center gap-2 font-mono text-xs font-semibold uppercase tracking-wider text-amber-300/90">
          🛡 hodl protection <span className="font-normal normal-case text-slate-500">— one-way, can never be undone</span>
        </div>
        <label className="mb-3 flex cursor-pointer items-start gap-3">
          <input
            type="checkbox"
            className="mt-0.5 h-4 w-4 accent-amber-400"
            checked={nonTransferable}
            onChange={(e) => setNonTransferable(e.target.checked)}
          />
          <span className="text-sm text-slate-300">
            Non-transferable
            <span className="block text-xs text-slate-500">
              The position NFT can never be moved or sold — a phished wallet can&apos;t lose it.
            </span>
          </span>
        </label>
        <span className="label">Pin payout to a cold wallet (optional)</span>
        <input
          className="input font-mono"
          placeholder="0x… — claims will only ever pay this address"
          value={payoutTo}
          onChange={(e) => setPayoutTo(e.target.value.trim())}
        />
        {!payoutValid && <div className="mt-1.5 text-xs text-rose-400">Not a valid address</div>}
        {wantsProtection && (
          <div className="mt-2 text-xs text-amber-300/80">
            ⚠ Protection is permanent. Double-check the payout address — not even you can
            change it later.
          </div>
        )}
      </div>

      {/* actions */}
      <div className="flex flex-col gap-3">
        {needsApproval && (
          <button
            className="btn-primary w-full"
            disabled={approving || approveConfirming || !parsedAmount}
            onClick={() =>
              token &&
              parsedAmount &&
              writeApprove({
                address: token,
                abi: erc20Abi,
                functionName: "approve",
                args: [vault, parsedAmount],
              })
            }
          >
            {approving || approveConfirming ? "Approving…" : `1 · Approve ${symbol ?? "token"}`}
          </button>
        )}
        <button className="btn-primary w-full" disabled={!ready || locking || lockConfirming} onClick={submit}>
          {locking || lockConfirming
            ? "Locking…"
            : needsApproval
              ? "2 · Lock"
              : mode === "timelock"
                ? "Lock it 🔒"
                : "Start vesting 🔒"}
        </button>
        {error && (
          <div className="rounded-xl border border-rose-500/20 bg-rose-500/10 px-4 py-3 text-xs text-rose-300">
            {(error as { shortMessage?: string }).shortMessage ?? error.message}
          </div>
        )}
        <p className="text-center text-xs text-slate-500">
          You&apos;ll receive an NFT representing this position. Protocol fee is deducted from
          the deposit (hard-capped at 1%).
        </p>
      </div>
    </div>
  );
}
