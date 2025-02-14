// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title DeployGoldToken
 * @notice Script de déploiement du contrat GoldBackedToken avec Foundry.
 *
 * Pour exécuter le déploiement (sans broadcast):
 *    forge script script/GoldToken.s.sol:DeployGoldToken \
 *      --rpc-url https://eth-sepolia.g.alchemy.com/v2/yn5r7HYQ2Nue5VNatnlauYywMOTTDeKc \
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

        console.log("------------------------------------------------");
        console.log(" Contrat GoldToken deployed at :");
        console.logAddress(address(goldToken));
        console.log("------------------------------------------------\n");

        console.log("=== MINT : Envoi de 0.5 ETH a mintGold() ===");
        goldToken.mintGold{value: 0.5 ether}();

        uint256 balanceAfterMint = goldToken.balanceOf(msg.sender);
        console.log("Balance GBT (msg.sender) apres mint:", balanceAfterMint);
        console.log('En format "token":', balanceAfterMint / 1e18, "GBT");
        console.log("------------------------------------------------\n");

        uint256 halfTokens = balanceAfterMint / 2;
        console.log("=== BURN : On brule la moitie des tokens recus ===");
        console.log("Amount to burn (wei of token):", halfTokens);
        goldToken.burnGold(halfTokens);

        uint256 balanceAfterBurn = goldToken.balanceOf(msg.sender);
        console.log("Balance GBT (msg.sender) apres burn:", balanceAfterBurn);
        console.log('En format "token":', balanceAfterBurn / 1e18, "GBT");
        console.log("------------------------------------------------\n");

        vm.stopBroadcast();
    }
}
