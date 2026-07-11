import type { Address } from "viem";

/**
 * LockVault deployment addresses per chain id.
 * Override / extend at build time with VITE_LOCKVAULT_ADDRESS (applies to all
 * configured chains) — handy for local hardhat nodes and fresh testnets.
 */
export const LOCKVAULT_ADDRESSES: Record<number, Address | undefined> = {
  1: undefined, // Ethereum mainnet — set after deployment
  8453: undefined, // Base
  42161: undefined, // Arbitrum One
  11155111: undefined, // Sepolia
  31337: "0x5FbDB2315678afecb367f032d93F642f64180aa3", // hardhat node, first deployment
};

const envAddress = import.meta.env.VITE_LOCKVAULT_ADDRESS as Address | undefined;

export function lockVaultAddress(chainId: number): Address | undefined {
  return envAddress ?? LOCKVAULT_ADDRESSES[chainId];
}

/** Native ETH sentinel used by LockVault. */
export const NATIVE_TOKEN = "0x0000000000000000000000000000000000000000" as Address;
