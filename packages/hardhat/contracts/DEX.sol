pragma solidity >=0.8.0 <0.9.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX
 * @author Steve P.
 * @notice this is a single token pair reserves DEX, ref: "Scaffold-ETH Challenge 2" as per https://speedrunethereum.com/challenge/token-vendor
 */
contract DEX {
    uint256 public totalLiquidity; //BAL token total liquidity in this contract
    mapping(address => uint256) public liquidity;

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(
        address swapper,
        string txDetails,
        uint256 ethInput,
        uint256 tokenOutput
    );

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(
        address swapper,
        string txDetails,
        uint256 tokensInput,
        uint256 ethOutput
    );

    /**
     * @notice Emitted when liquidity provided to DEX
     */
    event LiquidityProvided(
        address liquidityProvider,
        uint256 tokensInput,
        uint256 ethInput,
        uint256 liquidityMinted
    );

    /**
     * @notice Emitted when liquidity removed from DEX
     */
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 tokensOutput,
        uint256 ethOutput,
        uint256 liquidityWithdrawn
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the balance of this DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens)
        public
        payable
        returns (uint256 totalLiquidity)
    {
        require(totalLiquidity == 0, "init(): already has initial liquidity");

        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;

        require(
            token.transferFrom(msg.sender, address(this), tokens),
            "init(): failed to transfer tokens"
        );

        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public view returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput.mul(997);
        uint256 numerator = xInputWithFee.mul(yReserves);
        uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee);
        return (numerator / denominator);
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenAmount) {
        require(msg.value > 0, "ethToToken(): cannot swap 0 ETH");

        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenAmount = price(msg.value, ethReserve, tokenReserve);

        require(
            token.transfer(msg.sender, tokenAmount),
            "ethToToken(): Failed to transfer tokens"
        );

        emit EthToTokenSwap(
            msg.sender,
            "ethToToken(): Sold Balloons for ETHs",
            msg.value,
            tokenAmount
        );

        return tokenAmount;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenAmount)
        public
        returns (uint256 ethAmount)
    {
        require(tokenAmount > 0, "tokenToEth(): cannot purchase 0 tokens");

        require(
            token.transferFrom(msg.sender, address(this), tokenAmount),
            "tokenToEth(): failed to transfer tokens"
        );

        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethAmount = price(
            tokenAmount,
            tokenReserve,
            address(this).balance
        );

        (bool success, bytes memory data) = msg.sender.call{value: ethAmount}(
            ""
        );
        require(success, "tokenToEth(): failed to send eth to user");

        emit TokenToEthSwap(
            msg.sender,
            "Purchased Balloons for ETHs",
            ethAmount,
            tokenAmount
        );
        return ethAmount;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: Ratio needs to be maintained.
     */
    function deposit() public payable returns (uint256 tokens) {
        // do we need this? require(msg.vaue > 0, "deposit(): ETH must be > 0");

        // the eth before the payment
        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 tokenReserve = token.balanceOf(address(this));
        tokens = (msg.value.mul(tokenReserve) / ethReserve).add(1);

        uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
        liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
        totalLiquidity = totalLiquidity.add(liquidityMinted);

        require(
            token.transferFrom(msg.sender, address(this), tokens),
            "deposit(): failed to transfer tokens"
        );

        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokens);
        return tokens;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     */
    function withdraw(uint256 amount)
        public
        returns (uint256 ethOutput, uint256 tokenOutput)
    {
        // WTF is amount?
        // WTF is liquidity, what are we comparing here?
        require(
            liquidity[msg.sender] >= amount,
            "withdraw(): user does not have enough liquidity to withdraw."
        );

        // calculating amount of eth and token we can get based on reserves and liquidity.
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethOutput = amount.mul(ethReserve) / totalLiquidity;
        uint256 tokenOutput = amount.mul(tokenReserve) / totalLiquidity;

        // receiving ETHs and Tokens
        (bool success, bytes memory data) = payable(msg.sender).call{
            value: ethOutput
        }("");
        require(success, "tokenToEth(): failed to send eth to user");
        require(
            token.transfer(msg.sender, amount),
            "widthdraw(): failed to transfer tokens."
        );

        emit LiquidityRemoved(msg.sender, amount, ethOutput, tokenOutput);
        return (ethOutput, tokenOutput);
    }
}
