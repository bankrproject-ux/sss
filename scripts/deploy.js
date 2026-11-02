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
  console.log("       INPHIC DEPLOYER");
  console.log("================================\n");

  const privateKey = await askHidden(
    "Enter deployer private key (hidden): "
  );

  if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    throw new Error("Invalid private key format.");
  }

  const identityResolverInput = await ask(
    "Enter Agent ID Gate / Identity Resolver address: "
  );

  const treasuryInput = await ask(
    "Enter Treasury wallet address: "
  );

  let identityResolver;
  let treasury;

  try {
    identityResolver = hre.ethers.getAddress(identityResolverInput);
    treasury = hre.ethers.getAddress(treasuryInput);
  } catch {
    throw new Error("Invalid Gate or Treasury address.");
  }

  if (
    identityResolver === hre.ethers.ZeroAddress ||
    treasury === hre.ethers.ZeroAddress
  ) {
    throw new Error("Gate and Treasury addresses cannot be zero.");
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
  console.log("Contract: INPHIC");
  console.log("Network: BNB Smart Chain Mainnet");
  console.log("Chain ID: 56");
  console.log("Deployer:", deployer.address);
  console.log("Agent ID Gate:", identityResolver);
  console.log("Treasury:", treasury);

  console.log(
    "Deployer balance:",
    hre.ethers.formatEther(balance),
    "BNB"
  );

  console.log("\nINPHIC configuration");
  console.log("--------------------");
  console.log("Total supply: 500,000,000 INPHIC");
  console.log("Public allocation: 350,000,000 INPHIC");
  console.log("Free shares: 1,500");
  console.log("Paid shares: 2,000");
  console.log("Tokens per share: 100,000 INPHIC");
  console.log("Liquidity allocation: 80,000,000 INPHIC");
  console.log("Team / Treasury allocation: 50,000,000 INPHIC");
  console.log("Community reserve: 20,000,000 INPHIC");
  console.log("Network: BNB Smart Chain");

  const factory = await hre.ethers.getContractFactory(
    "INPHIC",
    deployer
  );

  // Constructor arguments
  const constructorArgs = [
    identityResolver,
    treasury
  ];

  const deployTx = await factory.getDeployTransaction(
    ...constructorArgs
  );

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

  console.log("\nPlease verify these addresses carefully:");
  console.log("Agent ID Gate:", identityResolver);
  console.log("Treasury:", treasury);

  const confirm = await ask(
    "\nDeploy INPHIC to MAINNET? Type DEPLOY to continue: "
  );

  if (confirm !== "DEPLOY") {
    console.log("Deployment cancelled. No transaction sent.");
    return;
  }

  console.log("\nDeploying INPHIC Contract...");

  const contract = await factory.deploy(
    ...constructorArgs
  );

  console.log("Transaction sent. Waiting for confirmation...");

  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  const deploymentTx = contract.deploymentTransaction();

  console.log("\n================================");
  console.log(" INPHIC DEPLOYED SUCCESSFULLY");
  console.log("================================");

  console.log("Contract address:", contractAddress);
  console.log("Deployer:", deployer.address);
  console.log("Agent ID Gate:", identityResolver);
  console.log("Treasury:", treasury);
  console.log("Transaction hash:", deploymentTx.hash);

  console.log(
    "Explorer:",
    `https://bscscan.com/address/${contractAddress}`
  );

  console.log("\nSave this INPHIC contract address.");
}

main().catch((error) => {
  console.error(
    "\nDeployment error:",
    error.shortMessage || error.message
  );

  process.exitCode = 1;
});
