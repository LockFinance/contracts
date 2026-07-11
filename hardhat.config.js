require("@nomicfoundation/hardhat-toolbox");

const {
  TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD,
} = require("hardhat/builtin-tasks/task-names");
const { subtask } = require("hardhat/config");

// Use the locally installed solc-js compiler (npm package) instead of
// downloading a native binary — keeps compilation working in offline /
// restricted-network environments.
subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args, hre, runSuper) => {
  if (args.solcVersion === "0.8.28") {
    return {
      compilerPath: require.resolve("solc/soljson.js"),
      isSolcJs: true,
      version: args.solcVersion,
      longVersion: "0.8.28",
    };
  }
  return runSuper(args);
});

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  networks: {
    hardhat: {},
    // Configure live networks via environment variables, e.g.:
    // mainnet: { url: process.env.RPC_URL, accounts: [process.env.PK] },
  },
  gasReporter: {
    enabled: false,
  },
};
