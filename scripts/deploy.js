const hre = require("hardhat");
const fs = require("fs");

const AzUsdABI = require("../artifacts/contracts/AzUsdCore.sol/AzUsdCore.json");
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
  const arbYieldContract = "0xBB801e24420e06B8dD32C5Da610FF876Bd510e4B";
  const uniAzusdContract = "0x9970dFeC70dFF5B432Fa09f946fB25ECcfbed248";
  let currentDomain;
  let destDomain;
  let destContract;
  let AzUsdCore;
  let AzUsdCoreAddress;
  let AzUsdYieldPool;
  let AzUsdYieldPoolAddress;

  if (chainId === 421614n) {
    currentDomain = arbDomain;
    destDomain = uniDomain;
    destContract = uniAzusdContract;
    USDCAddress = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
    AUSDCAddress = "0x460b97BD498E1157530AEb3086301d5225b91216";
    aavePool = "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff";
    aaveLock = 1;
    cctpTokenMessagerV2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
    cctpMessageTransmitterV2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";
    // const azUsdYieldPool = await hre.ethers.getContractFactory("AzUsdYieldPool");
    // AzUsdYieldPool = await azUsdYieldPool.deploy(
    //   USDCAddress,
    //   cctpTokenMessagerV2,
    //   cctpMessageTransmitterV2
    // );
    // AzUsdYieldPoolAddress = AzUsdYieldPool.target;
    AzUsdYieldPoolAddress = arbYieldContract;
  } else if (chainId === 1301n) {
    currentDomain = uniDomain;
    destDomain = arbDomain;
    destContract = arbYieldContract;
    USDCAddress = "0x31d0220469e10c4E71834a79b1f276d740d3768F";
    AUSDCAddress = "";
    aavePool = "";
    aaveLock = 0;
    cctpTokenMessagerV2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
    cctpMessageTransmitterV2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";

    // const azUsdCore = await hre.ethers.getContractFactory("AzUsdCore");
    // AzUsdCore = await azUsdCore.deploy(
    //   18,
    //   USDCAddress,
    //   cctpTokenMessagerV2,
    //   cctpMessageTransmitterV2,
    //   owner.address
    // );
    // AzUsdCoreAddress = AzUsdCore.target;
    AzUsdCoreAddress = uniAzusdContract;
  } else {
    throw "Invalid chain";
  }

  AzUsdCore = new ethers.Contract(AzUsdCoreAddress, AzUsdABI.abi, owner);
  console.log("AzUsdCore:", AzUsdCoreAddress);
  console.log("AzUsdYieldPoolAddress:", AzUsdYieldPoolAddress);

  if (aaveLock === 1) {
    const isActiveAave = await AzUsdYieldPool.isActiveAave();
    if (isActiveAave === false) {
      const setAaveInfo = await AzUsdYieldPool.setAaveInfo(
        0,
        aavePool,
        AUSDCAddress,
        true
      );
      const setAaveInfoTx = await setAaveInfo.wait();
      console.log("setAaveInfo:", setAaveInfoTx.hash);
    }
  }

  const USDC = new ethers.Contract(USDCAddress, ERC20ABI.abi, owner);

  async function BalanceOf(account, tokenContract) {
    const tokenBalance = await tokenContract.balanceOf(account);
    console.log("Token balance:", tokenBalance);
    return tokenBalance;
  }

  const minAllowance = hre.ethers.parseEther("100");
  const maxAllowance = hre.ethers.parseEther("10000000000");
  async function Approve(tokenContract, tokenOwner, tokenSpender) {
    const allowance = await tokenContract.allowance(tokenOwner, tokenSpender);
    console.log("allowance:", allowance);
    if (allowance < minAllowance) {
      const approve = await tokenContract.approve(tokenSpender, maxAllowance);
      const approveTx = await approve.wait();
      console.log("approve:", approveTx.hash);
    } else {
      console.log("Not approve");
    }
  }

  await BalanceOf(owner.address, USDC);
  await Approve(USDC, owner.address, AzUsdCoreAddress);

  const addressToBytes32 = await AzUsdCore.addressToBytes32(destContract);
  console.log("destContractToBytes32:", addressToBytes32);
  const setBytes32ValidContract = await AzUsdCore.setBytes32ValidContract(
    destDomain,
    addressToBytes32
  );
  const setBytes32ValidContractTx = await setBytes32ValidContract.wait();
  console.log("setBytes32ValidContract:", setBytes32ValidContractTx.hash);

  const Way = [0, 1];
  const mintAmount = 2n * 10n ** 4n;
  const getAmountOut1 = await AzUsdCore.getAmountOut(Way[0], mintAmount);
  console.log("getAmountOut1:", getAmountOut1);
  // const mint = await AzUsdCore.mint(
  //   destDomain,
  //   1500,
  //   USDCAddress,
  //   mintAmount,
  //   0
  // );
  // const mintTx = await mint.wait();
  // console.log("mint:", mintTx.hash);

  const refundAmount = 1_000_000_000_000_000n;
  const getAmountOut2 = await AzUsdCore.getAmountOut(Way[1], refundAmount);
  console.log("getAmountOut2:", getAmountOut2);
  const refund = await AzUsdCore.refund(destDomain, 1500, refundAmount, 0);
  const refundTx = await refund.wait();
  console.log("refund:", refundTx.hash);

  // const user1AzUsd = new ethers.Contract(AzUsdCoreAddress, AzUsdABI.abi, user1);

  config.Network = network.name;
  config.USDC = USDCAddress;
  config.AUSDC = AUSDCAddress;
  config.AavePool = aavePool;
  config.AzUsd = AzUsdCoreAddress;
  config.updateTime = new Date().toISOString();

  const filePath = "./deployedAddress.json";
  if (fs.existsSync(filePath)) {
    allAddresses = JSON.parse(fs.readFileSync(filePath, "utf8"));
  }
  allAddresses[chainId] = config;

  fs.writeFileSync(filePath, JSON.stringify(allAddresses, null, 2), "utf8");
  console.log("deployedAddress.json update:", allAddresses);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
