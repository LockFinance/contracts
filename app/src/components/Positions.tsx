import { useAccount, useChainId, useReadContract } from "wagmi";
import { lockVaultAbi } from "../abi/lockVault";
import { lockVaultAddress } from "../config";
import { PositionCard } from "./PositionCard";

export function Positions({ refreshKey }: { refreshKey: number }) {
  const { address } = useAccount();
  const chainId = useChainId();
  const vault = lockVaultAddress(chainId);

  const { data: ids, refetch } = useReadContract({
    address: vault,
    abi: lockVaultAbi,
    functionName: "positionsOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!vault },
    scopeKey: String(refreshKey),
  });

  if (!vault || !address) return null;

  if (!ids || ids.length === 0) {
    return (
      <div className="card px-6 py-12 text-center">
        <div className="mb-2 text-3xl">🌱</div>
        <div className="text-sm text-slate-400">
          No positions yet. Your locks will show up here as NFT positions.
        </div>
      </div>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2">
      {[...ids]
        .sort((a, b) => Number(b - a))
        .map((id) => (
          <PositionCard key={id.toString()} id={id} vault={vault} onChanged={() => refetch()} />
        ))}
    </div>
  );
}
