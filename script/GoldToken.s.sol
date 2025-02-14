// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/GoldToken.sol";

/**
 * @title DeployGoldToken
 * @notice Script de déploiement et de test du contrat GoldToken (loterie VRF).
 *
 * EXEMPLE de commande pour exécuter (avec broadcast sur le réseau) :
 * forge script script/GoldToken.s.sol:DeployGoldToken \
 *   --rpc-url $RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 *
 * Si tu utilises un .env, assure-toi d'avoir fait un "source .env" 
 * ou d'utiliser forge script ... --env .env
 */
contract DeployGoldToken is Script {
    function run() external {
        ///////////////////////////////////////////
        // 1. Lecture des variables d'environnement
        ///////////////////////////////////////////
        
        // Adresses Chainlink (pour feeds & VRF)
        address xauUsdFeed = vm.envAddress("XAU_USD_FEED");
        address ethUsdFeed = vm.envAddress("ETH_USD_FEED");
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");

        // Paramètres VRF
        uint64 subscriptionId = uint64(vm.envUint("VRF_SUB_ID"));
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");

        ///////////////////////////////////////////
        // 2. Lancement de la transaction 
        ///////////////////////////////////////////
        vm.startBroadcast();

        // Déploiement du contrat GoldToken
        GoldToken goldToken = new GoldToken(
            xauUsdFeed,
            ethUsdFeed,
            vrfCoordinator
        );

        // On configure le VRF (subId + keyHash)
        goldToken.setVRFParams(subscriptionId, keyHash);

        // Affiche l'adresse déployée
        console.log("------------------------------------------------");
        console.log(unicode" Contrat GoldToken déployé à :");
        console.logAddress(address(goldToken));
        console.log("------------------------------------------------\n");

        ///////////////////////////////////////////
        // 3. Test de quelques appels
        ///////////////////////////////////////////

        // MINT : Envoi de 0.001 ETH à mintGold()
        console.log(unicode"=== MINT : Envoi de 0.001 ETH à mintGold() ===");
        goldToken.mintGold{value: 0.001 ether}();

        uint256 balanceAfterMint = goldToken.balanceOf(msg.sender);
        console.log(unicode"Balance GBT (msg.sender) après mint:", balanceAfterMint);
        console.log("En format \"token\":", balanceAfterMint / 1e18, "GBT");
        console.log("------------------------------------------------\n");

        // BURN : On brûle la moitié des tokens reçus
        uint256 halfTokens = balanceAfterMint / 2;
        console.log(unicode"=== BURN : On brûle la moitié des tokens ===");
        console.log("Amount to burn (wei of token):", halfTokens);
        goldToken.burnGold(halfTokens);

        uint256 balanceAfterBurn = goldToken.balanceOf(msg.sender);
        console.log(unicode"Balance GBT (msg.sender) après burn:", balanceAfterBurn);
        console.log("En format \"token\":", balanceAfterBurn / 1e18, "GBT");
        console.log("------------------------------------------------\n");

        // Optionnel : on peut déclencher la loterie 
        // (si on veut voir l'appel VRF. Note : 
        //  il faut avoir un SubID valide avec LINK)
        console.log(unicode"=== LANCEMENT DE LA LOTTERIE (drawLottery) ===");
        try goldToken.drawLottery() returns (uint256 reqId) {
            console.log("drawLottery() called, requestId =", reqId);
        } catch {
            console.log(unicode"drawLottery() a échoué (peut-être subId/coord incorrect ?)");
        }
        console.log("------------------------------------------------\n");

        vm.stopBroadcast();
    }
}
