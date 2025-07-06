//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployTratoHechoP2P_CCTP } from "./DeployTratoHechoP2P_CCTP.s.sol";
import { DeployTratoHechoP2P } from "./DeployTratoHechoP2P.s.sol";

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    function run() external {
        // Deploys all your contracts sequentially
        // Add new deployments here when needed

        // Deploy TratoHechoP2P contract
        // DeployTratoHechoP2P deployTratoHechoP2P = new DeployTratoHechoP2P();
        // deployTratoHechoP2P.run();

        // Deploy TratoHechoP2P_CCTP contract
        DeployTratoHechoP2P_CCTP deployTratoHechoP2P_CCTP = new DeployTratoHechoP2P_CCTP();
        deployTratoHechoP2P_CCTP.run();

        // Deploy another contract
        // DeployMyContract myContract = new DeployMyContract();
        // myContract.run();
    }
}
