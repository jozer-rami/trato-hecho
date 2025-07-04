// packages/foundry/script/Deploy.s.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/OrderBookChainlinkTest.sol";

contract DeployScript is Script {
    error InvalidPrivateKey(string);

    function run() external {
        uint256 deployerPrivateKey = setupLocalhostEnv();
        
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockFunctionsRouter for testing
        MockFunctionsRouter mockRouter = new MockFunctionsRouter();
        console.log("MockFunctionsRouter deployed at:", address(mockRouter));
        
        // Deploy OrderBookChainlinkTest
        OrderBookChainlinkTest orderBook = new OrderBookChainlinkTest();
        console.log("OrderBookChainlinkTest deployed at:", address(orderBook));
        
        // Initialize with Chainlink configuration
        string memory sourceCode = getChainlinkSourceCode();
        orderBook.initialize(
            address(mockRouter),  // router
            1,                   // subscriptionId  
            keccak256("test-don"), // donID
            sourceCode           // sourceCode
        );
        
        // Configure mock router
        mockRouter.addAllowedSender(address(orderBook));
        
        console.log("OrderBook initialized with MockRouter");
        
        vm.stopBroadcast();
        
        /**
         * This function generates the file containing the contracts Abi definitions.
         * These definitions are used to derive the types needed in the custom scaffold-eth hooks, for example.
         * This function should be called last.
         */
        exportDeployments();
    }

    function setupLocalhostEnv() internal returns (uint256 forkId) {
        // Default timeout for localhost
        vm.createSelectFork({blockNumber: 1, urlOrAlias: "localhost"});
        return vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function exportDeployments() internal {
        // Write deployment addresses to file for frontend
        string memory deployments = string.concat(
            '{\n',
            '  "OrderBookChainlinkTest": "', vm.toString(address(0)), '",\n',
            '  "MockFunctionsRouter": "', vm.toString(address(0)), '"\n',
            '}'
        );
        
        vm.writeFile("../nextjs/contracts/deployedContracts.ts", deployments);
    }

    function getChainlinkSourceCode() internal pure returns (string memory) {
        return "const orderId = args[0];"
               "const bankingApiUrl = args[1];"
               "const apiKey = args[2];"
               "const expectedAmount = args[3];"
               "const buyerBankAccount = args[4];"
               "if (!orderId || !bankingApiUrl || !apiKey) {"
               "  throw Error('Missing required arguments');"
               "}"
               "const apiResponse = await Functions.makeHttpRequest({"
               "  url: `${bankingApiUrl}/api/v1/transfers/verify`,"
               "  method: 'POST',"
               "  headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },"
               "  data: { orderId: orderId, expectedAmount: expectedAmount, buyerAccount: buyerBankAccount }"
               "});"
               "if (apiResponse.error) {"
               "  throw Error(`Banking API error: ${apiResponse.error}`);"
               "}"
               "const responseData = apiResponse.data;"
               "if (!responseData || typeof responseData.confirmed !== 'boolean') {"
               "  throw Error('Invalid API response format');"
               "}"
               "const isValidTransfer = responseData.confirmed && "
               "                       responseData.orderId === orderId &&"
               "                       responseData.amount >= parseFloat(expectedAmount);"
               "return Functions.encodeUint256(isValidTransfer ? 1 : 0);";
    }
}