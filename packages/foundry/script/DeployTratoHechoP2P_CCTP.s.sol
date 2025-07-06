// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/TratoHechoP2P_CCTP.sol";

/**
 * @notice Deploy script for TratoHechoP2P_CCTP contract
 * @dev Inherits ScaffoldETHDeploy which:
 *      - Includes forge-std/Script.sol for deployment
 *      - Includes ScaffoldEthDeployerRunner modifier
 *      - Provides `deployer` variable
 * Example:
 * yarn deploy --file DeployTratoHechoP2P_CCTP.s.sol  # local anvil chain
 * yarn deploy --file DeployTratoHechoP2P_CCTP.s.sol --network sepolia # live network (requires keystore)
 */
contract DeployTratoHechoP2P_CCTP is ScaffoldETHDeploy {
    /**
     * @dev Deployer setup based on `ETH_KEYSTORE_ACCOUNT` in `.env`:
     *      - "scaffold-eth-default": Uses Anvil's account #9 (0xa0Ee7A142d267C1f36714E4a8F75612F20a79720), no password prompt
     *      - "scaffold-eth-custom": requires password used while creating keystore
     *
     * Note: Must use ScaffoldEthDeployerRunner modifier to:
     *      - Setup correct `deployer` account and fund it
     *      - Export contract addresses & ABIs to `nextjs` packages
     */
    function run() external ScaffoldEthDeployerRunner {
        // Deploy the P2P Exchange contract with CCTP support
        TratoHechoP2P_CCTP p2pExchange = new TratoHechoP2P_CCTP();
        
        console.log("TratoHechoP2P_CCTP deployed to:", address(p2pExchange));
        console.log("USDC Token address:", address(p2pExchange.usdcToken()));
        console.log("Owner:", p2pExchange.owner());
        
        // Log CCTP configuration
        console.log("\n=== CCTP Configuration ===");
        console.log("Token Messenger:", 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA);
        console.log("Message Transmitter:", 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275);
        console.log("Supported Domains:");
        console.log("  - Ethereum Sepolia: 0");
        console.log("  - Avalanche Fuji: 1");
        console.log("  - Arbitrum Sepolia: 3");
        console.log("  - Base Sepolia: 6");
        console.log("  - Polygon Amoy: 7");
        
        // Log deployment information
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Ethereum Sepolia");
        console.log("Contract: TratoHechoP2P_CCTP");
        console.log("Address:", address(p2pExchange));
        console.log("Gas Limit:", p2pExchange.gasLimit());
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contract on Etherscan");
        console.log("2. Create Chainlink Functions subscription");
        console.log("3. Fund subscription with LINK tokens");
        console.log("4. Add contract as consumer to subscription");
        console.log("5. Test with banking API integration");
        console.log("6. Test cross-chain USDC transfers via CCTP");
        
        // Save deployment info to file
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "contract": "TratoHechoP2P_CCTP",\n',
            '  "address": "', vm.toString(address(p2pExchange)), '",\n',
            '  "network": "ethereum-sepolia",\n',
            '  "usdc": "', vm.toString(address(p2pExchange.usdcToken())), '",\n',
            '  "owner": "', vm.toString(p2pExchange.owner()), '",\n',
            '  "gasLimit": ', vm.toString(p2pExchange.gasLimit()), ',\n',
            '  "cctp": {\n',
            '    "tokenMessenger": "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA",\n',
            '    "messageTransmitter": "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275",\n',
            '    "supportedDomains": {\n',
            '      "ethereumSepolia": 0,\n',
            '      "avalancheFuji": 1,\n',
            '      "arbitrumSepolia": 3,\n',
            '      "baseSepolia": 6,\n',
            '      "polygonAmoy": 7\n',
            '    }\n',
            '  }\n',
            "}"
        ));
        
        vm.writeFile("deployment.json", deploymentInfo);
        console.log("\nDeployment info saved to deployment.json");
    }
}

/**
 * @notice Setup script for TratoHechoP2P_CCTP contract
 * @dev Used to configure the contract after deployment
 * Example:
 * yarn deploy --file DeployTratoHechoP2P_CCTP.s.sol --sig "setup()" --network sepolia
 */
contract SetupTratoHechoP2P_CCTP is ScaffoldETHDeploy {
    function setup() external ScaffoldEthDeployerRunner {
        // Get the deployed contract address from deployments
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        
        // Read the deployment file to get the contract address
        string memory deploymentData = vm.readFile(path);
        address contractAddress = vm.parseJsonAddress(deploymentData, ".TratoHechoP2P_CCTP");
        
        TratoHechoP2P_CCTP p2p = TratoHechoP2P_CCTP(contractAddress);
        
        // Set optimal gas limit for Chainlink Functions
        p2p.setGasLimit(300000);
        
        console.log("Gas limit set to:", p2p.gasLimit());
        console.log("CCTP contract setup completed!");
        console.log("Contract supports cross-chain USDC transfers via CCTP");
    }
} 