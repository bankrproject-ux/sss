
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

async function getSigner() {
  const privateKey = await askHidden(
    "Enter owner/deployer private key (hidden): "
  );

  if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    throw new Error("Invalid private key format.");
  }

  const provider = hre.ethers.provider;
  const network = await provider.getNetwork();

  if (network.chainId !== 56n) {
    throw new Error(
      `Wrong network: chain ID ${network.chainId}. Expected BSC Mainnet 56.`
    );
  }

  const signer = new hre.ethers.Wallet(privateKey, provider);
  const balance = await provider.getBalance(signer.address);

  console.log("\nWallet:", signer.address);
  console.log(
    "BNB balance:",
    hre.ethers.formatEther(balance),
    "BNB"
  );

  return { signer, provider, balance };
}

// ======================================================
// DEPLOY INPHIC
// ======================================================

async function deployInphic() {
  console.log("\n========== DEPLOY INPHIC ==========\n");

  const { signer, provider, balance } = await getSigner();

  const treasuryInput = await ask(
    "Enter Treasury wallet address: "
  );

  let treasury;

  try {
    treasury = hre.ethers.getAddress(treasuryInput);
  } catch {
    throw new Error("Invalid Treasury address.");
  }

  if (treasury === hre.ethers.ZeroAddress) {
    throw new Error("Treasury address cannot be zero.");
  }

  const factory = await hre.ethers.getContractFactory(
    "INPHIC",
    signer
  );

  // Latest INPHIC constructor:
  // constructor(address payable _treasury)
  // Agent ID Gate is hardcoded in the Solidity contract.

  const constructorArgs = [treasury];

  const deployTx = await factory.getDeployTransaction(
    ...constructorArgs
  );

  const estimatedGas = await provider.estimateGas({
    ...deployTx,
    from: signer.address
  });

  const feeData = await provider.getFeeData();

  if (feeData.gasPrice === null) {
    throw new Error("Unable to retrieve current gas price.");
  }

  const estimatedCost = estimatedGas * feeData.gasPrice;
  const safetyCost = estimatedCost * 120n / 100n;

  console.log("\nDeployment configuration");
  console.log("------------------------");
  console.log("Contract: INPHIC");
  console.log("Network: BNB Smart Chain Mainnet");
  console.log("Chain ID: 56");
  console.log("Deployer:", signer.address);
  console.log(
    "Agent ID Gate:",
    "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F"
  );
  console.log("Treasury:", treasury);

  console.log(
    "Estimated gas:",
    estimatedGas.toString()
  );

  console.log(
    "Estimated cost:",
    hre.ethers.formatEther(estimatedCost),
    "BNB"
  );

  console.log(
    "Recommended balance:",
    hre.ethers.formatEther(safetyCost),
    "BNB"
  );

  if (balance < safetyCost) {
    throw new Error(
      "Insufficient BNB for deployment with 20% gas buffer."
    );
  }

  const confirm = await ask(
    "\nDeploy INPHIC to MAINNET? Type DEPLOY: "
  );

  if (confirm !== "DEPLOY") {
    console.log("Deployment cancelled. No transaction sent.");
    return;
  }

  console.log("\nDeploying INPHIC...");

  const contract = await factory.deploy(
    ...constructorArgs
  );

  console.log("Transaction sent. Waiting for confirmation...");

  await contract.waitForDeployment();

  const address = await contract.getAddress();
  const tx = contract.deploymentTransaction();

  console.log("\n================================");
  console.log(" INPHIC DEPLOYED SUCCESSFULLY");
  console.log("================================");

  console.log("Contract:", address);
  console.log("Deployer:", signer.address);
  console.log("Agent ID Gate:", "Hardcoded in contract");
  console.log("Treasury:", treasury);
  console.log("Transaction:", tx.hash);

  console.log(
    `Explorer: https://bscscan.com/address/${address}`
  );

  console.log("\nSave this INPHIC contract address.");
}

// ======================================================
// WITHDRAW RESIDUE
// ======================================================

async function withdrawResidue() {
  console.log("\n========== WITHDRAW RESIDUE ==========\n");

  const { signer, provider } = await getSigner();

  const contractInput = await ask(
    "Enter deployed INPHIC contract address: "
  );

  let contractAddress;

  try {
    contractAddress = hre.ethers.getAddress(contractInput);
  } catch {
    throw new Error("Invalid INPHIC contract address.");
  }

  const contract = await hre.ethers.getContractAt(
    "INPHIC",
    contractAddress,
    signer
  );

  const ownerAddress = await contract.owner();

  console.log("\nWithdraw configuration");
  console.log("----------------------");
  console.log("Contract:", contractAddress);
  console.log("Connected wallet:", signer.address);
  console.log("Contract owner:", ownerAddress);

  if (
    ownerAddress.toLowerCase() !== signer.address.toLowerCase()
  ) {
    throw new Error(
      "Access denied. Connected wallet is not the contract owner."
    );
  }

  const treasury = await contract.treasury();

  const contractBalance = await provider.getBalance(
    contractAddress
  );

  console.log("Treasury:", treasury);

  console.log(
    "Contract BNB balance:",
    hre.ethers.formatEther(contractBalance),
    "BNB"
  );

  if (contractBalance === 0n) {
    throw new Error("Contract has no BNB to withdraw.");
  }

  console.log("\nWARNING:");
  console.log("- Mint/sale will be stopped.");
  console.log("- Entire BNB balance will be sent to Treasury.");
  console.log("- All refund rights will be closed.");
  console.log("- This action cannot be undone.");

  const confirm = await ask(
    "\nExecute withdrawResidue()? Type WITHDRAW: "
  );

  if (confirm !== "WITHDRAW") {
    console.log("Withdraw cancelled. No transaction sent.");
    return;
  }

  console.log("\nSending withdraw transaction...");

  const tx = await contract.withdrawResidue();

  console.log("Transaction sent:", tx.hash);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();

  if (!receipt || receipt.status !== 1) {
    throw new Error("Withdraw transaction failed.");
  }

  const remainingBalance = await provider.getBalance(
    contractAddress
  );

  console.log("\n================================");
  console.log(" WITHDRAW SUCCESSFUL");
  console.log("================================");

  console.log("Contract:", contractAddress);
  console.log("Treasury:", treasury);
  console.log("Transaction:", tx.hash);

  console.log(
    "Remaining contract balance:",
    hre.ethers.formatEther(remainingBalance),
    "BNB"
  );

  console.log(
    `Explorer: https://bscscan.com/tx/${tx.hash}`
  );
}

// ======================================================
// MAIN MENU
// ======================================================

async function main() {
  console.log("\n================================");
  console.log("       INPHIC DEPLOYER");
  console.log("================================");

  console.log("1. Deploy INPHIC");
  console.log("2. Withdraw Residue");
  console.log("0. Exit");

  const choice = await ask("\nSelect menu: ");

  if (choice === "1") {
    await deployInphic();
  } else if (choice === "2") {
    await withdrawResidue();
  } else if (choice === "0") {
    console.log("Exited.");
  } else {
    throw new Error("Invalid menu selection.");
  }
}

main().catch((error) => {
  console.error(
    "\nDeployment error:",
    error.shortMessage || error.reason || error.message
  );

  process.exitCode = 1;
});
