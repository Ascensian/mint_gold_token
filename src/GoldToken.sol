// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title GoldToken
 * @author
 * @notice Un token ERC20 adossé au prix de l'or via Chainlink,
 *         avec une loterie via Chainlink VRF.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Chainlink Price Feeds
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Chainlink VRF v2
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract GoldToken is ERC20, Ownable, VRFConsumerBaseV2 {
    // ====================================================
    // ===================== Variables =====================
    // ====================================================

    AggregatorV3Interface public goldPriceFeed;
    AggregatorV3Interface public ethPriceFeed;
    uint256 public constant FEE_PERCENT = 5;

    // On choisit 18 décimales comme la plupart des tokens ERC20
    uint8 private constant DECIMALS = 18;

    // ---------------------
    // Variables VRF & Loterie
    // ---------------------
    VRFCoordinatorV2Interface private COORDINATOR;

    /// @notice Subscription ID pour Chainlink VRF
    uint64 private s_subscriptionId;

    /// @notice keyHash du job VRF sur le network
    bytes32 private s_keyHash;

    /**
     * @dev Pot de la loterie (en ETH).
     *  On alimente ce pot avec 50 % des frais prélevés.
     */
    uint256 public lotteryPot;

    /**
     * @dev On stocke la dernière adresse qui a fait un mint/burn.
     *  (Logique simple : si randomNumber % 2 == 0, elle gagne la loterie.)
     */
    address public lastParticipant;

    // ====================================================
    // ===================== Events ========================
    // ====================================================
    event Mint(address indexed sender, uint256 ethAmount, uint256 tokenAmount);
    event Burn(address indexed sender, uint256 tokenAmount, uint256 ethReturned);
    event LotteryWon(address indexed winner, uint256 amount);

    // ====================================================
    // ==================== Constructor ====================
    // ====================================================
    /**
     * @notice Initialise le contrat ERC20, fixe les oracles Chainlink,
     *         et définit l'adresse du VRF Coordinator (obligatoire
     *         pour l'immutable dans VRFConsumerBaseV2).
     *
     * @param _goldPriceFeed Adresse du feed Chainlink XAU/USD
     * @param _ethPriceFeed Adresse du feed Chainlink ETH/USD
     * @param _vrfCoordinator Adresse du VRFCoordinator sur le réseau
     */
    constructor(
        address _goldPriceFeed,
        address _ethPriceFeed,
        address _vrfCoordinator
    )
        ERC20("Gold Backed Token", "GBT")
        Ownable(msg.sender)             // On garde Ownable(msg.sender)
        VRFConsumerBaseV2(_vrfCoordinator) // On fixe l'adresse du coordinator ici
    {
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);

        // Optionnel, on peut init "vide"
        // s_subscriptionId = 0;
        // s_keyHash = 0;
        // On pourra les setter plus tard via setVRFParams(...)
        
        // On initialise COORDINATOR (qu'on utilisera pour requestRandomWords)
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    // ====================================================
    // =================== VRF Settings ====================
    // ====================================================
    /**
     * @notice Permet au owner de configurer la souscription et le keyHash du VRF.
     * @param _subId L'ID de la souscription Chainlink
     * @param _keyHash Le keyHash du job VRF à utiliser
     */
    function setVRFParams(uint64 _subId, bytes32 _keyHash)
        external
        onlyOwner
    {
        s_subscriptionId = _subId;
        s_keyHash = _keyHash;
    }

    // ====================================================
    // =================== ERC20 Setup =====================
    // ====================================================
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    // ====================================================
    // ================== Chainlink Getters ===============
    // ====================================================
    function getLatestGoldPrice() public view returns (int256) {
        (, int256 price, , , ) = goldPriceFeed.latestRoundData();
        return price;
    }

    function getLatestEthPrice() public view returns (int256) {
        (, int256 price, , , ) = ethPriceFeed.latestRoundData();
        return price;
    }

    // ====================================================
    // ====================== Mint =========================
    // ====================================================
    function mintGold() external payable {
        require(msg.value > 0, "No ETH sent");

        int256 ethPrice = getLatestEthPrice();
        require(ethPrice > 0, "Invalid ETH price");
        int256 goldPrice = getLatestGoldPrice();
        require(goldPrice > 0, "Invalid gold price");

        uint256 ethPriceUint = uint256(ethPrice); // 8 dec
        uint256 goldPriceUint = uint256(goldPrice); // 8 dec

                uint256 usdValue = (msg.value * ethPriceUint) / 1e26;

                uint256 gramsOfGoldIn1e18 = (usdValue * 1e26) / goldPriceUint;

        // 5% de frais => 95% pour l'utilisateur
        uint256 fee = (gramsOfGoldIn1e18 * FEE_PERCENT) / 100;
        uint256 netMintAmount = gramsOfGoldIn1e18 - fee;

        // On injecte 50% de la valeur en ETH de ce fee dans la loterie
        // 5% de l'ETH envoyé => (msg.value * 5/100)
        uint256 feeInEth = (msg.value * FEE_PERCENT) / 100; 
        uint256 halfFeeInEth = feeInEth / 2;
        lotteryPot += halfFeeInEth;
        lastParticipant = msg.sender;

        // Mint pour l'utilisateur
        _mint(msg.sender, netMintAmount);

        emit Mint(msg.sender, msg.value, netMintAmount);
    }

    // ====================================================
    // ====================== Burn ========================
    // ====================================================
    function burnGold(uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= _amount, "Not enough tokens");

// Prix XAU/USD
        int256 goldPrice = getLatestGoldPrice();
        require(goldPrice > 0, "Invalid gold price");

// Prix ETH/USD
        int256 ethPrice = getLatestEthPrice();
        require(ethPrice > 0, "Invalid ETH price");

        uint256 goldPriceUint = uint256(goldPrice);
        uint256 ethPriceUint = uint256(ethPrice);

        // Convertit tokens -> USD
        uint256 usdValue = (_amount * goldPriceUint) / 1e26;

        // Convertit USD -> ETH
        uint256 redemptionWei = (usdValue * 1e26) / ethPriceUint;

        // 5% de frais
        uint256 fee = (redemptionWei * FEE_PERCENT) / 100;
        uint256 netEth = redemptionWei - fee;

        // Burn tokens
        _burn(msg.sender, _amount);

        // Ajout de la moitié des frais au pot de loterie
        uint256 halfFee = fee / 2;
        lotteryPot += halfFee;
        lastParticipant = msg.sender;

        // L'utilisateur reçoit le reste
        (bool success, ) = msg.sender.call{value: netEth}("");
        require(success, "ETH transfer failed");

        emit Burn(msg.sender, _amount, netEth);
    }

    // ====================================================
    // ================== Lottery Functions ===============
    // ====================================================
    /**
     * @notice Le owner déclenche la loterie pour générer un random.
     */
    function drawLottery() external onlyOwner returns (uint256 requestId) {
        require(lotteryPot > 0, "No pot to win");
        require(address(COORDINATOR) != address(0), "VRF not configured");

        requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            3,          // requestConfirmations
            200000,     // callbackGasLimit
            1           // numWords
        );
    }

    /**
     * @notice Callback de Chainlink VRF.
     *         On verse la cagnotte à lastParticipant si random est pair.
     */
    function fulfillRandomWords(
        uint256, 
        uint256[] memory randomWords
    ) internal override {
        uint256 randomNumber = randomWords[0];

        // Simple logique: 1 chance sur 2
        if (randomNumber % 2 == 0) {
            uint256 prize = lotteryPot;
            lotteryPot = 0;

            (bool success, ) = lastParticipant.call{value: prize}("");
            require(success, "Lottery transfer failed");

            emit LotteryWon(lastParticipant, prize);
        }
        // Sinon, rien. On laisse la loterie pour un prochain drawLottery().
    }

    // ====================================================
    // ====================== Owner =======================
    // ====================================================
    /**
     * @notice Retrait des frais par le owner (solde - pot).
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        // On retire tout sauf le pot de la loterie
        uint256 available = balance - lotteryPot;
        require(available > 0, "No ETH to withdraw");

        (bool success, ) = owner().call{value: available}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}
