/**
 * Deploy LockVault.
 *
 * Usage:
 *   FEE_RECIPIENT=0x... FEE_BPS=50 npx hardhat run scripts/deploy.js --network <network>
 *
 * Defaults: deployer as owner and fee recipient, 50 bps (0.5%) fee.
 */
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const owner = process.env.OWNER ?? deployer.address;
  const feeRecipient = process.env.FEE_RECIPIENT ?? deployer.address;
  const feeBps = BigInt(process.env.FEE_BPS ?? "50");

  console.log(`Deployer:      ${deployer.address}`);
  console.log(`Owner:         ${owner}`);
  console.log(`Fee recipient: ${feeRecipient}`);
  console.log(`Fee:           ${feeBps} bps`);

  const LockVault = await ethers.getContractFactory("LockVault");
  const vault = await LockVault.deploy(owner, feeRecipient, feeBps);
  await vault.waitForDeployment();

  console.log(`\nLockVault deployed at: ${await vault.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
