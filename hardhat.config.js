require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.26",
  networks: {
    arb_sepolia: {
      chainId: 421614,
      url: process.env.Arbitrum_Sepolia_Rpc,
      accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
    },
    unichain_sepolia: {
      chainId: 1301,
      url: process.env.Unichain_Sepolia_RPC,
      accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
    }
  },
  solidity: {
    compilers: [{ version: "0.8.26" }],
    settings: {
      optimizer: {
        enabled: false,
        runs: 200,
      },
    },
  },
  gasReporter: {
    enabled: false,
    currency: "ETH",
    // coinmarketcap: 'YOUR_API_KEY',
    outputFile: "gas-report.txt",
    noColors: true,
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    // apiKey: process.env.
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 4000,
  },
};
