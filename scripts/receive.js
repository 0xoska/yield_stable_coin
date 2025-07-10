const hre = require("hardhat");
const { getAttestation } = require("./attestationservice");
const AzUsdCCTPV2ABI = require("../artifacts/contracts/AzUsdCCTPV2.sol/AzUsdCCTPV2.json");
const { Wallet } = require("ethers");

require("dotenv").config();
async function main() {
  const [owner] = await hre.ethers.getSigners();
  console.log("owner:", owner.address);
  const provider = ethers.provider;
  const network = await provider.getNetwork();
  const chainId = network.chainId;
  console.log("Chain ID:", chainId);

  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  const BYTES32_ZERO = "0x0000000000000000000000000000000000000000000000000000000000000000";
  const arbDomain = 3;
  const uniDomain = 10;
  let USDCAddress;
  let TokenMessagerV2;
  let MessageTransmitterV2;
  const arbAzUsdCCTPV2Address = "0xAdB599F381b731a1C7FaF8d31F8530feC05999aF";
  const uniAzUsdCCTPV2Address = "0x83bEde1230B62c1f1bA50c2BC673D94bDE45616F";
  let AzUsdCCTPV2Address;
  if (chainId === 421614n) {
    USDCAddress = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
    TokenMessagerV2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
    MessageTransmitterV2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";

    AzUsdCCTPV2Address = arbAzUsdCCTPV2Address;
  } else if (chainId === 1301n) {
    USDCAddress = "0x31d0220469e10c4E71834a79b1f276d740d3768F";
    TokenMessagerV2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
    MessageTransmitterV2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";

    AzUsdCCTPV2Address = uniAzUsdCCTPV2Address;
  } else {
    throw "Invalid chain";
  }
  const AttestationStatus = {
    COMPLETE: "complete",
    PENDING_CONFIRMATIONS: "pending_confirmations",
  };

  const arbProvider = new ethers.JsonRpcProvider(process.env.Arb_Sepolia_RPC);

  let attestation;
  let message;
  async function fetchPastEventsByHash(sourceDomainId) {
    try {
      const txHash =
        "0xa4ddba084d56cf95f24de229e46a1b24a27806488cf6043f445a526e282fef9c";
      const attestationResponse = await getAttestation(sourceDomainId, txHash);
      attestation = attestationResponse.attestation;
      message = attestationResponse.message;
      console.log("attestation:", attestation);
      console.log("========================================================");
      console.log("message:", message);
      return (attestation, message);
    } catch (e) {
      console.log("e:", e);
    }
  }

  // await fetchPastEvents();

  await fetchPastEventsByHash(3);


  const AzUsdCCTPV2 = new ethers.Contract(AzUsdCCTPV2Address, AzUsdCCTPV2ABI.abi, owner);
  console.log("AzUsdCCTPV2 address:", AzUsdCCTPV2Address);

  async function AddressToBytes32(account){
    const bytes32Account = await AzUsdCCTPV2.addressToBytes32(account);
    console.log("Bytes32 account", bytes32Account);
    return bytes32Account;
  }

  const bytes32ArbAzUsdCCTPV2 = await AddressToBytes32(arbAzUsdCCTPV2Address);
  const bytes32UniAzUsdCCTPV2 = await AddressToBytes32(uniAzUsdCCTPV2Address);

  // const setValidContract1 = await AzUsdCCTPV2.setValidContract(
  //   bytes32ArbAzUsdCCTPV2,
  //   true
  // );
  // const setValidContract1Tx = await setValidContract1.wait();
  // console.log("setValidContract1:", setValidContract1Tx.hash);

  // const setValidContract2 = await AzUsdCCTPV2.setValidContract(
  //   bytes32UniAzUsdCCTPV2,
  //   true
  // );
  // const setValidContract2Tx = await setValidContract2.wait();
  // console.log("setValidContract2:", setValidContract2Tx.hash);

  const decodeMessage = await AzUsdCCTPV2.decodeMessage(
    message
  );
  console.log("decodeMessage:", decodeMessage);

  const decodeMessageBody = await AzUsdCCTPV2.decodeMessageBody(
    decodeMessage[9]
  );
  console.log("decodeMessageBody:", decodeMessageBody);

  const decodeMessageToHookdata = await AzUsdCCTPV2.decodeMessageToHookdata(
    message
  );
  console.log("decodeMessageToHookdata:", decodeMessageToHookdata);

  // const receiveUSDC = await AzUsdCCTPV2.receiveUSDC(
  //   message,
  //   attestation
  // );
  // const receiveUSDCTx= await receiveUSDC.wait();
  // console.log("receiveUSDCTx:", receiveUSDCTx.hash);

  const receiveAmount = await AzUsdCCTPV2.receiveAmount();
  console.log("receiveAmount:", receiveAmount);

  const receiver = await AzUsdCCTPV2.receiver();
  console.log("receiver:", receiver);

  //   setInterval(async () => {
  //     await fetchPastEventsByHash(3);
  //   }, 10000);

  // setInterval(async () => {
  //     await fetchPastEvents();
  // }, 25000);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
