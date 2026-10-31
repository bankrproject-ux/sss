
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
    let finished = false;

    function cleanup() {
      if (finished) return;
      finished = true;

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
  console.log("      VORT CLAIM DEPLOYER");
  console.log("================================\n");

  const privateKey = await askHidden(
    "Enter deployer private key (hidden): "
  );

  if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    throw new Error("Invalid private key format.");
  }

  const provider = hre.ethers.provider;
  const network = await provider.getNetwork();

  if (network.chainId !== 56n) {
    throw new Error(
      `Wrong network: chain ID ${network.chainId}. Expected 56.`
    );
  }

  const deployer = new hre.ethers.Wallet(privateKey, provider);
  const balance = await provider.getBalance(deployer.address);

  console.log("\nDeployment configuration");
  console.log("------------------------");
  console.log("Contract: VORTClaim");
  console.log("Network: BNB Smart Chain Mainnet");
  console.log("Chain ID: 56");
  console.log("Deployer:", deployer.address);

  console.log(
    "Deployer balance:",
    hre.ethers.formatEther(balance),
    "BNB"
  );

  console.log("\nClaim configuration");
  console.log("-------------------");
  console.log("NFT: 0xb8a529f9bb1eedd3def2f5178678c447c646d034b");
  console.log("Token: 0x8629f95ef3c0ea98cb1944964e640a9cc135c889");
  console.log("Fee wallet: 0x50d5247defa13922c89a6276d725844b905fa73b");
  console.log("Reward: 50,000 VORT per NFT");
  console.log("Claim fee: 0.0002 BNB per NFT");
  console.log("Maximum allocation: 444,400,000 VORT");

  const factory = await hre.ethers.getContractFactory(
    "VORTClaim",
    deployer
  );

  const deployTx = await factory.getDeployTransaction();

  const estimatedGas = await provider.estimateGas({
    ...deployTx,
    from: deployer.address
  });

  const feeData = await provider.getFeeData();
  const gasPrice = feeData.gasPrice;

  if (gasPrice === null) {
    throw new Error("Unable to retrieve current gas price.");
  }

  const estimatedCost = estimatedGas * gasPrice;
  const safetyCost = estimatedCost * 120n / 100n;

  console.log(
    "\nEstimated deployment gas:",
    estimatedGas.toString()
  );

  console.log(
    "Estimated deployment cost:",
    hre.ethers.formatEther(estimatedCost),
    "BNB"
  );

  console.log(
    "Recommended minimum balance:",
    hre.ethers.formatEther(safetyCost),
    "BNB"
  );

  if (balance < safetyCost) {
    throw new Error(
      "Insufficient BNB for deployment with 20% gas buffer."
    );
  }

  const confirm = await ask(
    "\nDeploy VORT CLAIM to MAINNET? Type DEPLOY to continue: "
  );

  if (confirm !== "DEPLOY") {
    console.log("Deployment cancelled. No transaction sent.");
    return;
  }

  console.log("\nDeploying VORT Claim Contract...");

  const contract = await factory.deploy();

  console.log("Transaction sent. Waiting for confirmation...");

  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  const deploymentTx = contract.deploymentTransaction();

  console.log("\n================================");
  console.log(" VORT CLAIM DEPLOYED SUCCESSFULLY");
  console.log("================================");

  console.log("Contract address:", contractAddress);
  console.log("Deployer:", deployer.address);
  console.log("Transaction hash:", deploymentTx.hash);

  console.log(
    "Explorer:",
    `https://bscscan.com/address/${contractAddress}`
  );

  console.log("\nSave this VORT Claim Contract address.");
  console.log("Fund it with 444,400,000 VORT before enabling claims.");
}

main().catch((error) => {
  console.error(
    "\nDeployment error:",
    error.shortMessage || error.message
  );

  process.exitCode = 1;
});
