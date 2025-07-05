// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Deploy on Arbitrum Sepolia

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/resources/link-token-contracts/
 */

/**
 * @title GettingStartedFunctionsConsumer
 * @notice This is an example contract to show how to make HTTP requests using Chainlink
 * @dev This contract uses hardcoded values and should not be used in production.
 */
contract GettingStartedFunctionsConsumer is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    // State variables to store the last request ID, response, and error
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    // Event to log responses
    event Response(
        bytes32 indexed requestId,
        string status,
        bytes response,
        bytes err
    );

    // Hardcoded for Ethereum Sepolia
    // Supported networks https://docs.chain.link/chainlink-functions/supported-networks
    address router = 0x234a5fb5Bd614a7AA2FfAB244D603abFA0Ac5C5C;
    bytes32 donID = 0x66756e2d617262697472756d2d7365706f6c69612d3100000000000000000000;

    //Callback gas limit
    uint32 gasLimit = 300000;

    // JavaScript source code
    // Fetch status name from the Star Wars API.
    // Documentation: https://swapi.dev/documentation#people
    string source =
        "const referenceId = args[0];"
        "const bankingApiUrl = 'https://bnb-bank-api.ngrok.app';"
        "const apiRequest = Functions.makeHttpRequest({"
            "url: `${bankingApiUrl}/DirectDebit/GetTransactionOutgoing/${referenceId}`,"
            "method: 'GET',"
            "headers: {"
            "Authorization: `Bearer ${secrets.apiKey}`,"
            "},"
        "});"
        "const apiResponse = await apiRequest;"
        "console.log('API response data:', JSON.stringify(apiResponse, null, 2));"
        "if (apiResponse.error) {"
            "throw Error('Banking API request failed');"
        "}"
        "const responseData = apiResponse.data;"
        "return Functions.encodeString(responseData.status);";


    // State variable to store the returned status information
    string public status;

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor() FunctionsClient(router) ConfirmedOwner(msg.sender) {}

    /**
     * @notice Sends an HTTP request for status information
     * @param subscriptionId The ID for the Chainlink subscription
     * @param args The arguments to pass to the HTTP request
     * @return requestId The ID of the request
     */
    function sendRequest(
        uint64 subscriptionId,
        string[] calldata args
    ) external onlyOwner returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (args.length > 0) req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        return s_lastRequestId;
    }

    /**
     * @notice Callback function for fulfilling a request
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     * @param err Any errors from the Functions request
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId); // Check if request IDs match
        }
        // Update the contract's state variables with the response and any errors
        s_lastResponse = response;
        status = string(response);
        s_lastError = err;

        // Emit an event to log the response
        emit Response(requestId, status, s_lastResponse, s_lastError);
    }
}