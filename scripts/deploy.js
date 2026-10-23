
const hre = require("hardhat");
const readline = require("readline");
const { stdin, stdout } = require("process");

function ask(question) {
  const rl = readline.createInterface({
    input: stdin,
    output: stdout
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function askHidden(question) {
  return new Promise((resolve, reject) => {
    if (!stdin.isTTY || typeof stdin.setRawMode !== "function") {
      reject(new Error("Run this script in an interactive CMD terminal."));
      return;
    }

    stdout.write(question);

    let value = "";

    function cleanup() {
      stdin.removeListener("data", onData);
      stdin.setRawMode(false);
      stdin.pause();
    }

    function onData(char) {
      const key = char.toString();

      if (key === "\u0003") {
        cleanup();
        stdout.write("\n");
        reject(new Error("Cancelled."));
        return;
      }

      if (key === "\r" || key === "\n") {
        cleanup();
        stdout.write("\n");
        resolve(value.trim());
        return;
      }

      if (key === "\u007f" || key === "\b") {
        value = value.slice(0, -1);
        return;
      }

      if (key >= " " && key <= "~") {
        value += key;
      }
    }

    stdin.setRawMode(true);
    stdin.resume();
    stdin.on("data", onData);
  });
}

async function main() {
  console.log("\n================================");
  console.log("       ORVYN NFT DEPLOYER");
  console.log("================================\n");

  const privateKey = await askHidden(
    "Enter deployer private key (hidden): "
  );

  if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    throw new Error("Invalid private key format.");
  }

  const ownerWallet = await ask("Enter owner wallet address: ");

  if (!hre.ethers.isAddress(ownerWallet)) {
    throw new Error("Invalid owner wallet address.");
  }

  const network = await hre.ethers.provider.getNetwork();

  if (network.chainId !== 56n) {
    throw new Error(
      `Wrong network: chain ID ${network.chainId}. Expected 56.`
    );
  }

  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(privateKey, provider);

  const balance = await provider.getBalance(deployer.address);

  console.log("\nDeployment configuration");
  console.log("------------------------");
  console.log("Network: BNB Smart Chain Mainnet");
  console.log("Chain ID: 56");
  console.log("Deployer:", deployer.address);
  console.log("Owner:", ownerWallet);
  console.log("Deployer balance:", hre.ethers.formatEther(balance), "BNB");

  const feeData = await provider.getFeeData();
  const factory = await hre.ethers.getContractFactory(
    "ORVYN",
    deployer
  );

  const deployTx = await factory.getDeployTransaction(ownerWallet);
  const estimatedGas = await provider.estimateGas({
    ...deployTx,
    from: deployer.address
  });

  const gasPrice = feeData.gasPrice;

  if (gasPrice === null) {
    throw new Error("Unable to retrieve current gas price.");
  }

  const estimatedCost = estimatedGas * gasPrice;

  console.log(
    "Estimated deployment gas:",
    estimatedGas.toString()
  );

  console.log(
    "Estimated deployment cost:",
    hre.ethers.formatEther(estimatedCost),
    "BNB"
  );

  if (balance < estimatedCost) {
    throw new Error("Insufficient BNB for estimated deployment gas.");
  }

  const confirm = await ask(
    "\nDeploy ORVYN to MAINNET? Type DEPLOY to continue: "
  );

  if (confirm !== "DEPLOY") {
    console.log("Deployment cancelled. No transaction sent.");
    return;
  }

  console.log("\nDeploying ORVYN...");

  const contract = await factory.deploy(ownerWallet);
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  const deploymentTx = contract.deploymentTransaction();

  console.log("\n================================");
  console.log("    ORVYN DEPLOYED SUCCESSFULLY");
  console.log("================================");
  console.log("Contract address:", contractAddress);
  console.log("Owner wallet:", ownerWallet);
  console.log("Deployer wallet:", deployer.address);
  console.log("Transaction hash:", deploymentTx.hash);
  console.log(
    "Explorer:",
    `https://bscscan.com/address/${contractAddress}`
  );
  console.log("\nSave the contract address for verification.");
}

main().catch((error) => {
  console.error("\nDeployment error:", error.shortMessage || error.message);
  process.exitCode = 1;
});
