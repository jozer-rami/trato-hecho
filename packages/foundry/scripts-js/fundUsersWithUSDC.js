const { ethers } = require("hardhat");

// USDC token address on Ethereum Sepolia
const USDC_ADDRESS = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";

// Sample user addresses (same as in the Solidity script)
const USERS = {
    ALICE: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    BOB: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", 
    CHARLIE: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
    DAVID: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
};

// USDC ABI (minimal for balance checking and transfer)
const USDC_ABI = [
    "function balanceOf(address owner) view returns (uint256)",
    "function transfer(address to, uint amount) returns (bool)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)"
];

async function main() {
    console.log("=== USDC Balance Checker ===");
    console.log("Network: Ethereum Sepolia");
    console.log("USDC Address:", USDC_ADDRESS);
    console.log("");

    // Get signer
    const [deployer] = await ethers.getSigners();
    console.log("Deployer address:", deployer.address);
    console.log("Deployer balance:", ethers.formatEther(await deployer.getBalance()), "ETH");
    console.log("");

    // Connect to USDC contract
    const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, deployer);
    
    // Check deployer's USDC balance
    const deployerUSDCBalance = await usdc.balanceOf(deployer.address);
    const decimals = await usdc.decimals();
    const symbol = await usdc.symbol();
    
    console.log("Deployer USDC balance:", ethers.formatUnits(deployerUSDCBalance, decimals), symbol);
    console.log("");

    // Check each user's balance
    console.log("=== User USDC Balances ===");
    for (const [name, address] of Object.entries(USERS)) {
        const balance = await usdc.balanceOf(address);
        console.log(`${name}: ${ethers.formatUnits(balance, decimals)} ${symbol}`);
    }
    console.log("");

    // Calculate required amounts for orders
    const orderAmounts = {
        ALICE: 0.1,   // 0.1 USDC
        BOB: 0.2,     // 0.2 USDC  
        CHARLIE: 0.3, // 0.3 USDC
        DAVID: 0.4    // 0.4 USDC
    };

    console.log("=== Required USDC for Orders ===");
    for (const [name, amount] of Object.entries(orderAmounts)) {
        const userAddress = USERS[name];
        const currentBalance = await usdc.balanceOf(userAddress);
        const requiredAmount = ethers.parseUnits(amount.toString(), decimals);
        
        console.log(`${name}:`);
        console.log(`  Required: ${amount} ${symbol}`);
        console.log(`  Current: ${ethers.formatUnits(currentBalance, decimals)} ${symbol}`);
        
        if (currentBalance >= requiredAmount) {
            console.log(`  ✅ Sufficient balance`);
        } else {
            console.log(`  ❌ Insufficient balance`);
            console.log(`  Need to transfer: ${ethers.formatUnits(requiredAmount - currentBalance, decimals)} ${symbol}`);
        }
        console.log("");
    }

    // Option to fund users (commented out for safety)
    console.log("=== Funding Instructions ===");
    console.log("To fund users with USDC, you can:");
    console.log("1. Use a faucet to get USDC on Sepolia");
    console.log("2. Transfer USDC from your wallet to the user addresses");
    console.log("3. Or uncomment the funding code below and run this script");
    console.log("");

    // Uncomment the following code to actually fund users
    /*
    console.log("Funding users with USDC...");
    for (const [name, address] of Object.entries(USERS)) {
        const amount = orderAmounts[name];
        const amountInWei = ethers.parseUnits(amount.toString(), decimals);
        
        console.log(`Funding ${name} with ${amount} ${symbol}...`);
        const tx = await usdc.transfer(address, amountInWei);
        await tx.wait();
        console.log(`✅ ${name} funded successfully!`);
    }
    */
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 