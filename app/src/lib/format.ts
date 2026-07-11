import { formatUnits } from "viem";

export function formatAmount(value: bigint, decimals: number, maxFrac = 4): string {
  const s = formatUnits(value, decimals);
  const [whole, frac = ""] = s.split(".");
  const trimmed = frac.slice(0, maxFrac).replace(/0+$/, "");
  const withSep = Number(whole) > 999 ? Number(whole).toLocaleString("en-US") : whole;
  return trimmed ? `${withSep}.${trimmed}` : withSep;
}

export function shortAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function formatDate(ts: number | bigint): string {
  return new Date(Number(ts) * 1000).toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Human-readable remaining time, e.g. "42d 7h" or "3h 12m". */
export function timeRemaining(untilTs: number | bigint): string {
  const seconds = Number(untilTs) - Math.floor(Date.now() / 1000);
  if (seconds <= 0) return "now";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

/** datetime-local input value → unix seconds */
export function inputToUnix(value: string): number {
  return Math.floor(new Date(value).getTime() / 1000);
}

/** unix seconds N days from now, formatted for a datetime-local input */
export function defaultUnlockInput(daysFromNow: number): string {
  const d = new Date(Date.now() + daysFromNow * 86400_000);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
}
