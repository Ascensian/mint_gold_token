// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title GoldToken
 * @author
 * @notice Un token ERC20 adossé au prix de l'or via Chainlink.
 *
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GoldToken is ERC20, Ownable {
    // ====================================================
    // ===================== Variables =====================
    // ====================================================

    AggregatorV3Interface public goldPriceFeed;
    AggregatorV3Interface public ethPriceFeed;
    uint256 public constant FEE_PERCENT = 5;

    /// @dev On choisit 18 décimales comme la plupart des tokens ERC20
    uint8 private constant DECIMALS = 18;

    // ====================================================
    // ===================== Events ========================
    // ====================================================
    /**
     * @notice Émis lorsqu'un utilisateur mint des tokens et envoie de l'ETH
     * @param sender L'adresse qui a mint
     * @param ethAmount La quantité d'ETH envoyée (en wei)
     * @param tokenAmount La quantité finale de tokens reçus
     */
    event Mint(address indexed sender, uint256 ethAmount, uint256 tokenAmount);

    /**
     * @notice Émis lorsqu'un utilisateur burn des tokens et reçoit de l'ETH
     * @param sender L'adresse qui a burn
     * @param tokenAmount La quantité de tokens burn
     * @param ethReturned La quantité d'ETH renvoyée (en wei) après frais
     */
    event Burn(
        address indexed sender,
        uint256 tokenAmount,
        uint256 ethReturned
    );

    // ====================================================
    // ==================== Constructor ====================
    // ====================================================
    /**
     * @notice Initialise le contrat ERC20 et fixe les oracles Chainlink.
     * @param _goldPriceFeed Adresse du feed Chainlink XAU/USD
     * @param _ethPriceFeed Adresse du feed Chainlink ETH/USD
     */
    constructor(
        address _goldPriceFeed,
        address _ethPriceFeed
    ) ERC20("Gold Backed Token", "GBT") Ownable(msg.sender) {
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);
    }

    // ====================================================
    // =================== ERC20 Setup =====================
    // ====================================================

    /**
     * @notice Redéfinition éventuelle si on veut forcer 18 décimales
     * @return Nombre de décimales du token
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    // ====================================================
    // ================== Chainlink Getters ===============
    // ====================================================

    /**
     * @notice Récupère le prix de l'or (XAU) en USD depuis Chainlink
     * @dev Le feed XAU/USD a typiquement 8 décimales
     * @return price Le prix de l'or en USD (avec 8 décimales)
     */
    function getLatestGoldPrice() public view returns (int256) {
        (
            ,
            /*uint80 roundId*/
            int256 price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = goldPriceFeed.latestRoundData();
        return price;
    }

    /**
     * @notice Récupère le prix de l'ETH en USD depuis Chainlink
     * @dev Le feed ETH/USD a typiquement 8 décimales
     * @return price Le prix de l'ETH en USD (avec 8 décimales)
     */
    function getLatestEthPrice() public view returns (int256) {
        (, int256 price, , , ) = ethPriceFeed.latestRoundData();
        return price;
    }

    // ====================================================
    // ====================== Mint =========================
    // ====================================================
    /**
     * @notice Permet de frapper (mint) des tokens en échange d'ETH.
     * @dev  L'utilisateur envoie de l'ETH, on calcule la quantité de GBT
     *       en se basant sur les prix XAU/USD et ETH/USD. 1 GBT = 1 gramme.
     *       On applique 5% de frais (non remis à l'utilisateur).
     */
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

        uint256 fee = (gramsOfGoldIn1e18 * FEE_PERCENT) / 100;
        uint256 netMintAmount = gramsOfGoldIn1e18 - fee;

        _mint(msg.sender, netMintAmount);

        emit Mint(msg.sender, msg.value, netMintAmount);
    }

    // ====================================================
    // ====================== Burn ========================
    // ====================================================
    /**
     * @notice Permet de brûler (burn) des tokens et de récupérer de l'ETH
     * @dev  L'utilisateur rend ses tokens (1 GBT = 1 g) et reçoit l'équivalent
     *       en ETH. 5% de frais sont déduits sur la valeur retournée.
     * @param _amount Quantité de tokens à brûler (en 18 décimales)
     */
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

        uint256 usdValue = (_amount * goldPriceUint) / 1e26;

        uint256 redemptionWei = (usdValue * 1e26) / ethPriceUint;

        uint256 fee = (redemptionWei * FEE_PERCENT) / 100;
        uint256 netEth = redemptionWei - fee;

        _burn(msg.sender, _amount);

        (bool success, ) = msg.sender.call{value: netEth}("");
        require(success, "ETH transfer failed");

        emit Burn(msg.sender, _amount, netEth);
    }

    // ====================================================
    // ====================== Owner =======================
    // ====================================================

    /**
     * @notice Le propriétaire peut retirer les frais collectés (ETH restant)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
