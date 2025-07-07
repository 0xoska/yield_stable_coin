const hre = require("hardhat");
const fs = require("fs");

const ERC20ABI = require("../artifacts/contracts/TestToken.sol/TestToken.json");

async function main() {
  const [owner] = await hre.ethers.getSigners();
  console.log("owner:", owner.address);

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
    AUSDCAddress = "";
    aavePool = "";
    aaveLock = true;
  } else if (chainId === 1301n) {
    USDCAddress = "0x31d0220469e10c4E71834a79b1f276d740d3768F";
    AUSDCAddress = "0x460b97BD498E1157530AEb3086301d5225b91216";
    aavePool = "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff";
    aaveLock = false;
  } else {
    throw "Invalid chain";
  }

  const azUsdCore = await hre.ethers.getContractFactory("AzUsdCore");
  const AzUsdCore = await azUsdCore.deploy(18, USDCAddress);
  const AzUsdCoreAddress = AzUsdCore.target;
  console.log("AzUsdCore:", AzUsdCoreAddress);

  if (aaveLock === false) {
    const setAaveInfo = await AzUsdCore.setAaveInfo(
      0,
      aavePool,
      AUSDCAddress,
      true
    );
    const setAaveInfoTx = await setAaveInfo.wait();
    console.log("setAaveInfo:", setAaveInfoTx.hash);
  }

  const Way = [0, 1, 2, 3];
  const mintAmount = 10n * 10n ** 6n;
  const mint = await AzUsdCore.mint(Way[0], mintAmount);
  const mintTx = await mint.wait();
  console.log("mint:", mintTx.hash);

  const refundAmount = 10n * 10n ** 18n;
  const refund = await AzUsdCore.refund(Way[1], refundAmount);
  const refundTx = await refund.wait();
  console.log("refund:", refundTx.hash);

  const receiver = "";
  const endTime = "";
  const amount = "";
  const flow = await AzUsdCore.flow(Way[3], receiver, endTime, amount);
  const flowTx = await flow.wait();
  console.log("flow:", flowTx.hash);

  async function Approve(token, spender, amount) {
    try {
      const tokenContract = new ethers.Contract(token, ERC20ABI.abi, owner);
      const allowance = await tokenContract.allowance(owner.address, spender);
      if (allowance < ethers.parseEther("10000")) {
        const approve = await tokenContract.approve(spender, amount);
        const approveTx = await approve.wait();
        console.log("approveTx:", approveTx.hash);
      } else {
        console.log("Not approve");
      }
    } catch (e) {
      console.log("e:", e);
    }
  }

  config.Network = network.name;
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
