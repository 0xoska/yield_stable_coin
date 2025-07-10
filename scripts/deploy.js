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

  if (chainId === 421614n) {
    USDCAddress = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
    AUSDCAddress = "0x460b97BD498E1157530AEb3086301d5225b91216";
    aavePool = "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff";
    aaveLock = 1;
  } else if (chainId === 1301n) {
    USDCAddress = "0x31d0220469e10c4E71834a79b1f276d740d3768F";
    AUSDCAddress = "";
    aavePool = "";
    aaveLock = 0;
  } else {
    throw "Invalid chain";
  }

  // const azUsdCore = await hre.ethers.getContractFactory("AzUsdCore");
  // const AzUsdCore = await azUsdCore.deploy(18, USDCAddress);
  // const AzUsdCoreAddress = AzUsdCore.target;
  const AzUsdCoreAddress = "0x3C6BBaaE23Af600537a90AD61A60F8F1aaF2e1BC";
  const AzUsdCore = new ethers.Contract(AzUsdCoreAddress, AzUsdABI.abi, owner);
  console.log("AzUsdCore:", AzUsdCoreAddress);

  if (aaveLock === 1) {
    const isActiveAave = await AzUsdCore.isActiveAave();
    if(isActiveAave === false){
      const setAaveInfo = await AzUsdCore.setAaveInfo(
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

  async function BalanceOf(account, tokenContract){
    const tokenBalance = await tokenContract.balanceOf(account);
    console.log("Token balance:", tokenBalance);
    return tokenBalance;
  }

  const minAllowance = hre.ethers.parseEther("100");
  const maxAllowance = hre.ethers.parseEther("10000000000");
  async function Approve(tokenContract, tokenOwner, tokenSpender){
    const allowance = await tokenContract.allowance(tokenOwner, tokenSpender);
    console.log("allowance:", allowance);
    if(allowance < minAllowance){
      const approve = await tokenContract.approve(tokenSpender, maxAllowance);
      const approveTx = await approve.wait();
      console.log("approve:", approveTx.hash);
    }else{
      console.log("Not approve")
    }
  }

  await BalanceOf(owner.address, USDC);
  await Approve(USDC, owner.address, AzUsdCoreAddress);

  const Way = [0, 1, 2, 3];
  const mintAmount = 1n * 10n ** 3n;
  const getAmountOut1 = await AzUsdCore.getAmountOut(Way[0], mintAmount);
  console.log("getAmountOut1:", getAmountOut1);
  // const mint = await AzUsdCore.mint(mintAmount);
  // const mintTx = await mint.wait();
  // console.log("mint:", mintTx.hash);

  const refundAmount = 1_000_000_000_000_000n;
  const getAmountOut2 = await AzUsdCore.getAmountOut(Way[1], refundAmount);
  console.log("getAmountOut2:", getAmountOut2);
  // const refund = await AzUsdCore.refund(refundAmount);
  // const refundTx = await refund.wait();
  // console.log("refund:", refundTx.hash);

  const endTime = 100;
  const amount = 1000;

  // const flow1 = await AzUsdCore.flow(Way[2], user1.address, endTime, amount);
  // const flow1Tx = await flow1.wait();
  // console.log("flow1:", flow1Tx.hash);

  // const flow2 = await AzUsdCore.flow(Way[3], user1.address, endTime, amount);
  // const flow2Tx = await flow2.wait();
  // console.log("flow2:", flow2Tx.hash);

  const user1AzUsd = new ethers.Contract(AzUsdCoreAddress, AzUsdABI.abi, user1);

  const indexUserStreams = await user1AzUsd.indexUserStreams(
    user1.address,
    0
  );
  console.log("indexUserStreams:", indexUserStreams);

  const release = await user1AzUsd.release(0);
  const releaseTx = await release.wait();
  console.log("release:", releaseTx.hash);

  config.Network = network.name;
  config.USDC= USDCAddress;
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
