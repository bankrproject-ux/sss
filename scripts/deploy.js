
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
      reject(
        new Error("Hidden input requires an interactive terminal.")
      );
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
        reject(new Error("Input cancelled."));
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
  console.log("\n==============================");
  console.log("     ORVYN NFT DEPLOYER");
  console.log("==============================\n");

  const privateKey = await askHidden(
    "Enter deployer private key (hidden): "
  );

  if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    throw new Error("Invalid private key format.");
  }

  const owner = await ask("Enter owner wallet address: ");

  if (!hre.ethers.isAddress(owner)) {
    throw new Error("Invalid owner wallet address.");
  }

  const baseURI = await ask(
    "Enter metadata base URI (IPFS, when ready): "
  );

  if (!baseURI.startsWith("ipfs://")) {
    throw new Error("Metadata URI must start with ipfs://");
  }

  const provider = hre.ethers.provider;
  const network = await provider.getNetwork();

  if (network.chainId !== 56n) {
    throw new Error("Wrong network. Expected BNB Smart Chain Mainnet.");
  }

  const wallet = new hre.ethers.Wallet(
    privateKey,
    provider
  );

  console.log("\nDeployer:", wallet.address);
  console.log("Owner:", owner);
  console.log("Network: BNB Smart Chain Mainnet");

  const balance = await provider.getBalance(wallet.address);
  console.log(
    "Deployer balance:",
    hre.ethers.formatEther(balance),
    "BNB"
  );

  console.log(
    "\nDeployment will be enabled after ORVYN.sol is finalized."
  );
  console.log("No transaction has been sent.");

  // The contract factory and deployment will be added
  // after the final ORVYN.sol constructor is confirmed.
}

main().catch((error) => {
  console.error("\nError:", error.message);
  process.exitCode = 1;
});
