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
  let uniContractAddress = "0x6Bb65a41103DD7df9D3585Aee692756A0D3B4908";
  let arbContractAddress = "0x34Ca9B7C78dE1B3e863E2Fb5D56fA2FCD790869b";

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

  const recipient = await AzUsdCCTPV2.addressToBytes32(destContractAddress);
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

  const messageBody = "";
  const handleSender = await AzUsdCCTPV2.addressToBytes32(cctpMessageTransmitterV2);
  console.log("handleSender:", handleSender);
  //receive message
  const handleReceiveFinalizedMessage = await AzUsdCCTPV2.handleReceiveFinalizedMessage(
    destDomain,
    handleSender,
    messageBody
  );
  const handleReceiveFinalizedMessageTx = await handleReceiveFinalizedMessage.wait();
  console.log("handleReceiveFinalizedMessage:", handleReceiveFinalizedMessageTx.hash);

    // const message =
    //   "";
    // const attestation =
    //   "";
    // const receiveUSDCAndData = await AzUsdCCTPV2.receiveUSDCAndData(
    //   message,
    //   attestation
    // );
    // const receiveUSDCAndDataTx = await receiveUSDCAndData.wait();
    // console.log("receiveUSDCAndData:", receiveUSDCAndDataTx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
