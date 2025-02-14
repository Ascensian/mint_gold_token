// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title DeployGoldBToken
 * @notice Script de déploiement du contrat GoldBackedToken avec Foundry.
 *
 * Pour exécuter le déploiement (sans broadcast):
 *    forge script script/DeployGoldBackedToken.s.sol:DeployGoldBackedToken \
 *      --rpc-url $RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 *
 */

import "forge-std/Script.sol";
import "../src/GoldToken.sol";

contract DeployGoldToken is Script {
    address public constant XAU_USD_FEED_MAINNET =
        0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea;
    address public constant ETH_USD_FEED_MAINNET =
        0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function run() external {
        vm.startBroadcast();

        GoldToken goldToken = new GoldToken(
            XAU_USD_FEED_MAINNET,
            ETH_USD_FEED_MAINNET
        );

        console.log("GoldToken deployed at:", address(goldToken));

        vm.stopBroadcast();
    }
}
