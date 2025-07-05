// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/TratoHechoP2P.sol";

/**
 * @notice Deploy script for TratoHechoP2P contract
 * @dev Inherits ScaffoldETHDeploy which:
 *      - Includes forge-std/Script.sol for deployment
 *      - Includes ScaffoldEthDeployerRunner modifier
 *      - Provides `deployer` variable
 * Example:
 * yarn deploy --file DeployTratoHechoP2P.s.sol  # local anvil chain
 * yarn deploy --file DeployTratoHechoP2P.s.sol --network sepolia # live network (requires keystore)
 */
contract DeployTratoHechoP2P is ScaffoldETHDeploy {
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
        // Deploy the P2P Exchange contract
        TratoHechoP2P p2pExchange = new TratoHechoP2P();
        
        console.log("TratoHechoP2P deployed to:", address(p2pExchange));
        console.log("USDC Token address:", address(p2pExchange.usdcToken()));
        console.log("Owner:", p2pExchange.owner());
        
        // Log deployment information
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Ethereum Sepolia");
        console.log("Contract: TratoHechoP2P");
        console.log("Address:", address(p2pExchange));
        console.log("Gas Limit:", p2pExchange.gasLimit());
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contract on Etherscan");
        console.log("2. Create Chainlink Functions subscription");
        console.log("3. Fund subscription with LINK tokens");
        console.log("4. Add contract as consumer to subscription");
        console.log("5. Test with banking API integration");
        
        // Save deployment info to file
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "contract": "TratoHechoP2P",\n',
            '  "address": "', vm.toString(address(p2pExchange)), '",\n',
            '  "network": "ethereum-sepolia",\n',
            '  "usdc": "', vm.toString(address(p2pExchange.usdcToken())), '",\n',
            '  "owner": "', vm.toString(p2pExchange.owner()), '",\n',
            '  "gasLimit": ', vm.toString(p2pExchange.gasLimit()), '\n',
            "}"
        ));
        
        vm.writeFile("deployment.json", deploymentInfo);
        console.log("\nDeployment info saved to deployment.json");
    }
}

/**
 * @notice Setup script for TratoHechoP2P contract
 * @dev Used to configure the contract after deployment
 * Example:
 * yarn deploy --file DeployTratoHechoP2P.s.sol --sig "setup()" --network sepolia
 */
contract SetupTratoHechoP2P is ScaffoldETHDeploy {
    function setup() external ScaffoldEthDeployerRunner {
        // Get the deployed contract address from deployments
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        
        // Read the deployment file to get the contract address
        string memory deploymentData = vm.readFile(path);
        address contractAddress = vm.parseJsonAddress(deploymentData, ".TratoHechoP2P");
        
        TratoHechoP2P p2p = TratoHechoP2P(contractAddress);
        
        // Set optimal gas limit for Chainlink Functions
        p2p.setGasLimit(300000);
        
        console.log("Gas limit set to:", p2p.gasLimit());
        console.log("Setup completed!");
    }
} 