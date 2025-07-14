const hre = require("hardhat");
const fs = require("fs");

const AzUsdCCTPV2ABI = require("../artifacts/contracts/AzUsdCCTPV2.sol/AzUsdCCTPV2.json");
const ERC20ABI = require("../artifacts/contracts/TestToken.sol/TestToken.json");

async function main() {
  const [owner, user1] = await hre.ethers.getSigners();
  console.log("owner:", owner.address);
  console.log("user1:", user1.address);

  const provider = ethers.provider;
  const network = await provider.getNetwork();
  const chainId = network.chainId;
  console.log("Chain ID:", chainId);

  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  let config = {};

  async function sendETH(toAddress, amountInEther) {
    const amountInWei = ethers.parseEther(amountInEther);
    const tx = {
      to: toAddress,
      value: amountInWei,
    };
    const transactionResponse = await owner.sendTransaction(tx);
    await transactionResponse.wait();
    console.log("Transfer eth success");
  }

  let allAddresses = {};

  let USDCAddress;
  let AUSDCAddress;
  let aavePool;
  let aaveLock;
  let cctpTokenMessagerV2;
  let cctpMessageTransmitterV2;
  const arbDomain = 3;
  const uniDomain = 10;
  let currentDomain;
  let destDomain;
  let currentContractAddress;
  let destContractAddress;
  let uniContractAddress = "0xBd387f849d0B387a55f17b7E5309c0ad0b65b58c";
  let arbContractAddress = "0xeA220A1B85A42937Dd996752354DEe54EF77cae0";

  if (chainId === 421614n) {
    currentContractAddress = arbContractAddress;
    destContractAddress = uniContractAddress;
    currentDomain = arbDomain;
    destDomain = uniDomain;
    USDCAddress = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
    AUSDCAddress = "0x460b97BD498E1157530AEb3086301d5225b91216";
    aavePool = "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff";
    aaveLock = 1;
    cctpTokenMessagerV2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
    cctpMessageTransmitterV2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";
  } else if (chainId === 1301n) {
    currentContractAddress = uniContractAddress;
    destContractAddress = arbContractAddress;
    currentDomain = uniDomain;
    destDomain = arbDomain;
    USDCAddress = "0x31d0220469e10c4E71834a79b1f276d740d3768F";
    AUSDCAddress = "";
    aavePool = "";
    aaveLock = 0;
    cctpTokenMessagerV2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
    cctpMessageTransmitterV2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";
  } else {
    throw "Invalid chain";
  }

  //   const azUsdCCTPV2 = await hre.ethers.getContractFactory("AzUsdCCTPV2");
  //   const AzUsdCCTPV2 = await azUsdCCTPV2.deploy(
  //     cctpTokenMessagerV2,
  //     cctpMessageTransmitterV2
  //   );
  //   const AzUsdCCTPV2Address = AzUsdCCTPV2.target;
  //   console.log("AzUsdCCTPV2Address:", AzUsdCCTPV2Address);

  const AzUsdCCTPV2 = new ethers.Contract(
    currentContractAddress,
    AzUsdCCTPV2ABI.abi,
    owner
  );

  const recipient = await AzUsdCCTPV2.addressToBytes32(cctpTokenMessagerV2);
  console.log("recipient:", recipient);

//   const crossMessage = await AzUsdCCTPV2.crossMessage(
//     USDCAddress,
//     destDomain,
//     recipient,
//     recipient,
//     2000,
//     2000
//   );
//   const crossMessageTx = await crossMessage.wait();
//   console.log("crossMessage:", crossMessageTx.hash);

  const messageBody = "0x0000000100000000000000000000000031d0220469e10c4e71834a79b1f276d740d3768f000000000000000000000000ea220a1b85a42937dd996752354dee54ef77cae00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bd387f849d0b387a55f17b7e5309c0ad0b65b58c00000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000640000000000000000000000000e913a977dfba823686de8066da9590c9c9ad344";

  //receive message
  const handleReceiveFinalizedMessage = await AzUsdCCTPV2.handleReceiveFinalizedMessage(
    destDomain,
    recipient,
    messageBody
  );
  const handleReceiveFinalizedMessageTx = await handleReceiveFinalizedMessage.wait();
  console.log("handleReceiveFinalizedMessage:", handleReceiveFinalizedMessageTx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
