# Links
- [Try it Live!](https://mwrites-dex.surge.sh/)
- [Original Version](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90)
- https://github.com/squirtleDevs/scaffold-eth/tree/challenge-3-single-pool-dex
- [spreedsheet that lets you tweak the values in yellow to see the other amounts change. It should help you conceptualize ](https://docs.google.com/spreadsheets/d/1iWCFlzdEXdn2DHmUdc7Oz-2r29piPj8anOctjlQsZUg/edit?usp=sharing)
- https://hackernoon.com/formulas-of-uniswap-a-deep-dive


---
# What
[[DEX]]

# Why
[[DEX]]

# How
We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will be funded by depositors (also called LP or liquidity providers).

These reserves will provide liquidity that allows anyone to swap between the assets.

The pricing of the tokens will be influenced by the ratio betwen ETH and Balloons. Indeed, for an Automated Market Maker to survive and be useful, it needs to always have liquidity. 

So we want to strive for a ratio of 50:50 between ETH and Balloons. We can create a pricing algorithm based on the current ratios.

---

# Deployment
Before diving into the implementation, let's look at the deployment to understand the flow.

If you are deploying a new token, create a ERC20 contract, otherwise just get the address of an existing ERC20 contract (??? TEST THIS)

Optional, create a ERC20 contract:
```js
  await deploy("Balloons", {
    // Learn more about args here: https://www.npmjs.com/package/hardhat-deploy#deploymentsdeploy
    from: deployer,
    // args: [ "Hello", ethers.utils.parseEther("1.5") ],
    log: true,
  });
```

Construct our DEX with the ERC20 contract address, (here it is balloons):
```js
	// ERC20 Contract
  const balloons = await ethers.getContract("Balloons", deployer);
	
  await deploy("DEX", {
    // Learn more about args here: https://www.npmjs.com/package/hardhat-deploy#deploymentsdeploy
    from: deployer,
    args: [balloons.address],
    log: true,
    waitConfirmations: 5,
  });
```

Optional, gift some ballons to a temporary address:
```js
// paste in your front-end address here to get 10 balloons on deploy:
  await balloons.transfer(
    "0x9A68B6258AcCC01Fc0260BBf86fD86D03B4a5Ce1",
    "" + 10 * 10 ** 18
  );
```


We need to fund the DEX with an inial amount of balloons, since we are transfering ERC20 tokens we will need to go through the [[Vendor#Approve Pattern]].

First we approve an allowance of 100 🎈 Ballons (not Ethers):
```js
// uncomment to init DEX on deploy:
console.log(
    "Approving DEX (" + dex.address + ") to take Balloons from main account..."
);

// If you are going to the testnet make sure your deployer account has enough ETH
await balloons.approve(dex.address, ethers.utils.parseEther("100"));
```

If we follow the approve pattern, at this point we would need to do a  `tokenTransferForm()`. Instead, we will use a function to initialize the fund. That function will do the actual transfer and do other book keeping things internally.

We want to send a amount of tokens and pay in Ether which translates to this function signature:
```solidity
function init(uint256 tokens) public payable 
```

We initialize the fund with 5 balloons and 5 ethers. The `parseEther()` is here to help us do the 10^18 math:
```js
console.log("INIT exchange...");
await dex.init(ethers.utils.parseEther("5"), {
	value: ethers.utils.parseEther("5"),
    gasLimit: 200000,
});
```

**Quiz Time**:
- [ ] Do you remember why we need to use the allowance pattern?
- [ ] Can you guess why we would need a separate `init()` function instead of a  `deposit()`. If you don't it's ok we will go back to this later.

---

# Recipe
Now that we understand the deployment flow, let's implement the contracts.

### 1. 🪙 Token
First we need to add the token that the reserve will hold. Use an existing ERC20 Token or create a [[Create ERC20 Token]]. 

Inject that ERC20 Contract into the constructor:
```solidity
contract DEX {
	IERC20 token; //instantiates the imported contract
  
    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }
}
```
> If you forgot what is the ERC20 token recipe, you can review the [[Token Vendor]] challenge.

### 2.  🏦 Creating the Reserve
Let's track the total amount of tokens we have. We also want to know how much each depositors added:
```
uint256 public totalLiquidity;
mapping (address => uint256) public liquidity;
```

**Quiz Time**:
- [ ] Can you guess why do we need to track the liquidity of each depositors?

Let's make a draft version. As we have seen in the deployment phase, we need a function to do the initial deposit:
```solidity
function init(uint256 tokens) public payable {
  totalLiquidity = address(this).balance;
  liquidity[msg.sender] = totalLiquidity;
  
  token.transferFrom(msg.sender, address(this), tokens));
}
```
- We can keep track of the `totalLiquidity`.
- We also keep track of how the liquidity by depositor.
- ETH has been paid thanks to the `payable` keyword on our function, but we still need to tell the ERC20 contract to transfer tokens from the sender to the DEX.

Now that you understand the gist of it, let's make it safer:
```solidity
function init(uint256 tokens) public payable returns (uint256 totalLiquidity) {
  require(totalLiquidity == 0, "init(): already has initial liquidity");
  
  totalLiquidity = address(this).balance;
  liquidity[msg.sender] = totalLiquidity;
  
  require(token.transferFrom(msg.sender, address(this), tokens), "init(): failed to transfer tokens");
  
  return totalLiquidity;
}

```
- We check for errors with `require`.
- And return the totalLiquidity.

**Quiz Time:**
- [ ] Why are we only keep track of ETH liquidity?
- [ ] Do you remember what is the difference between `token.transfer()` and `toke.transferFrom()`? Why does `token.transferFrom()` needs approve while `token.transfer()` doesn't?
- [ ] Can you guess why we would need a separate `init()` function instead of a  `deposit()`. If you don't it's ok we will go back to this later.


### 3. 💹 Trading
What does a DEX do again? A DEX is an exchange, so we need to provide a function to exchange tokens. Let's add functions to purchase and sell tokens:

**Purchasing Tokens**

We will allow users to buy tokens in exchange of ETH. Given the amount of ETH paid, the DEX will transfer and return the amount of token purchased:
```solidity
function ethToToken() public payable returns (uint256 tokenAmount)
```

A first draft:
```solidity
function ethToToken() public payable returns (uint256 tokenAmount) {
	uint256 ethReserve = address(this).balance.sub(msg.value);
    uint256 tokenReserve = token.balanceOf(address(this));

	uint256 tokenAmount = price(msg.value, ethReserve, tokenReserve);
	token.transfer(msg.sender, tokenAmount);

	return tokenAmount;
}
```
Let's look at it from bottom to top:
1. We tell the ERC20 contract to transfer `tokenAmount` of tokens.
2. To know how much tokens the user can buy, we need a `price` function.
3. The `price` function will: Given the current ratio of ETH/Tokens and the ETH paid, tell us how many tokens the user can buy.
4. We get the reserves of ETH and Tokens in our DEX.
5. Finally note the `payable` keyword which does the ETH payment for us.

A more complete version:
```
event EthToTokenSwap(address payer, string txDetails, uint256 ethAmount, uint256 tokenAmount);    
    
function ethToToken() public payable returns (uint256 tokenAmount) {
	require(msg.value > 0, "ethToToken(): cannot swap 0 ETH");

	uint256 ethReserve = address(this).balance.sub(msg.value);
	uint256 tokenReserve = token.balanceOf(address(this));
	uint256 tokenAmount = price(msg.value, ethReserve, tokenReserve);

	require(token.transfer(msg.sender, tokenAmount), "ethToToken(): Failed to transfer tokens");
	
	emit EthToTokenSwap(msg.sender, "ethToToken(): Sold Balloons for ETHs", msg.value, tokenAmount);
	
	return tokenAmount;
}

```
- We can check for errors with `require`.
- We define and `emit` an event for the purchase.
- We return the amount of token purchased.

**Quick Time:**
- [ ] Why do we need to do `balance.sub(msg.value)` ? Is balance updated before or after payable?
- [ ] Why are we not using `token.transferFrom()` here?
- [ ] If `token.transfer()` fails, what happen to the ETH paid?
- [ ] Do we need the user to do the approve before calling this function?


**Selling Tokens**
We will allow users to sell tokens to gain ETH. Given an amount of tokens, we will transfer and return the amount of ETH gained:
```solidity
function tokenToEth(tokenAmount) public returns (uint256 ethAmount)
```

A first draft:
```solidity
function tokenToEth(tokenAmount) public returns (uint256 ethAmount) {
	token.transferFrom(msg.sender, address(this), tokenAmount);

	uint256 ethReserve = address(this).balance;
	uint256 tokenReserve = token.balanceOf(address(this));
	uint256 ethAmount = price(tokenAmount, tokenReserve, ethReserve);

	(bool success, bytes memory data) = _to.call{value: ethAmount}("");
	return ethAmount;
}
```
Let's look at it from bottom to top:
1. We pay ETH to the user. ([[Send Ether]])
2. Before sending ETH, we need to figure out how much ETH we can send.
3. Here comes the `price` function again which will, given the current ratio of ETH/Tokens and the ETH paid, tell us how much ETHs the user will receive.
4. Pay attention to the order of arguments for `price`, it is not the same as in `ethToToken`!
5. Get the reserves, you know the drill. But this time we just need the current balance of ether: `.balance`.
6. We need to sell the tokens, so like in the initial deposit, we tell the ERC20 contract to `token.transferFrom()`  tokens.

A complete version:
```solidity
event TokenToEthSwap(address payer, string txDetails, uint256 tokenAmount, uint256 ethAmount);

function tokenToEth(uint256 tokenAmount) public returns (uint256 ethAmount) {
	require(tokenAmount > 0, "tokenToEth(): cannot purchase 0 tokens");

	require(token.transferFrom(msg.sender, address(this), tokenAmount), "tokenToEth(): failed to transfer tokens");

	uint256 ethReserve = address(this).balance;
	uint256 tokenReserve = token.balanceOf(address(this));
	uint256 ethAmount = price(tokenAmount, tokenReserve, address(this).balance);

	(bool success, bytes memory data) = msg.sender.call{value: ethAmount}("");
	require(success, "tokenToEth(): failed to send eth to user");
	
	emit TokenToEthSwap(msg.sender, "Purchased Balloons for ETHs", ethAmount, tokenAmount);
	return ethAmount;
}
```
- Error handling with `require`.
- Define and `emit`  an event for 🎈 balloons purchased.


- [ ] Do you remember what the use of `token.transferFrom()` implies?

### 3. 🏷 Pricing

We have used the `price` function in the token exchange functions. It is time to implement this function. We want to use a simple formula to determine the exchange rate between the two.


###  4. 🌊 Liquidity
**Depositing Liquidity**
So far, only the `init()` function controls liquidity. To make this more decentralized, it would be better if anyone could add to the liquidity pool by sending the DEX both ETH and tokens at the correct ratio.

Let’s create two new functions that let us deposit and withdraw liquidity. How would you write this function out? Try before taking a peak!

We need to deposit both tokens and ETH:
- [ ] How do you transfer ETH to a contract?
- [ ] Why can't we just put the amount of Tokens in the function argument?
- [ ] How do you send ERC20 Tokens to a contract?
- [ ] Remember to keep track of total liquidity and liquidity by depositors.

- 💡 Hint: Here's what the signature should look like:
```
function deposit() public payable
```


🔑  Solution:
```solidity
event LiquidityProvided(address payer, uint256 tokenInput, uint256 ethInput, uint256 liquidityMinted);


function deposit() public payable returns (uint256 tokens) {
	// do we need this? require(msg.vaue > 0, "deposit(): ETH must be > 0");

	// the eth before the payment
	uint256 ethReserve = address(this).balance.sub(msg.value);
	uint256 tokenReserve = token.balanceOf(address(this));
	tokens = (msg.value.mul(tokenReserve) / ethReserve).add(1);

	uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
	liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
	totalLiquidity = totalLiquidity.add(liquidityMinted);

	require(token.transferFrom(msg.sender, address(this), tokens), "deposit(): failed to transfer tokens");

	emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokens);
	return tokens;
}
```
From bottom to top:
1. Token transfer is handled by  `token.transferFrom`.
2. We figure out the equivalent of tokens that will be deposited based on reserves ratio and the ETH paid.
3. We also need to keep track of the liquidity.
4. ETH transfer is handled by the `payable` keyword.

Since we are using `token.transferFrom` the user will have to give the DEX approval to spend their tokens on their behalf by calling the `approve()` function prior to this function call. After the `deposit()` is called, equals parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.

**Quiz Time:**
- [ ] Do you understand why we need to do the `.sub` in `ethReserve = address(this).balance.sub(msg.value);`
- [ ] Do you understand why `tokens = (msg.value.mul(tokenReserve) / ethReserve).add(1);` ?
- [ ] Do you understand why `liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;`

**Withdrawing Liquidity**

The `withdraw()` function lets a user take both ETH and $BAL tokens out at the correct ratio. The actual amount of ETH and tokens a liquidity provider withdraws could be higher than what they deposited because of the 0.3% fees collected from each trade. It also could be lower depending on the price fluctuations of $BAL to ETH and vice versa (from token swaps taking place using your AMM!). The 0.3% fee incentivizes third parties to provide liquidity, but they must be cautious of [Impermanent Loss (IL)](https://www.youtube.com/watch?v=8XJ1MSTEuU0&t=2s&ab_channel=Finematics).

**Guides:**
- [ ] Which function will you use to transfer ETH to the user?
- [ ] Which function will you use to transfer Tokens to the user?
- [ ] How to calcualte the amount of ETH and Token?


💡 Hint: 


🔑 Solution:
```solidity
function withdraw(uint256 amount) public returns (uint256 ethOutput, uint256 tokenOutput) {
	// WTF is amount?
	// WTF is liquidity, what are we comparing here?
	require(liquidity[msg.sender] >= amount, "withdraw(): user does not have enough liquidity to withdraw.");

	// calculating amount of eth and token we can get based on reserves and liquidity.
	uint256 ethReserve = address(this).balance;
	uint256 tokenReserve = token.balanceOf(address(this));
	uint256 ethOutput = amount.mul(ethReserve) / totalLiquidity;
	uint256 tokenOutput = amount.mul(tokenReserve) / totalLiquidity;

	// receiving ETHs and Tokens
	(bool success, bytes memory data) = payable(msg.sender).call{ value: ethOutput}("");
	require(success, "tokenToEth(): failed to send eth to user");
	require(token.transfer(msg.sender, amount), "widthdraw(): failed to transfer tokens.");

	emit LiquidityRemoved(msg.sender, amount, ethOutput, tokenOutput);
	return (ethOutput, tokenOutput);
}
```
From bottom to top:
1. We update liquidity.
2. To send Tokens, instead of using `transferFrom` we can directly use `transfer` because we are not taking Tokens from the user, we are giving Tokens.
3. We can send ETH as we did in `tokenToEth()`.
4. But before that we need to figure out how much ETHs and Tokens we can withdraw with: `amount * reserve / totalLiquidity`
5. 

> With this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.

**Quiz Time:**
- [ ] Why are we using `token.transfer` instead of `token.transferFrom`?
- [ ] Why do we need to add `payable()`?
- [ ] What is liquidity actually? Eth, Balloons or???

### 🥅 Goals / Checks

Remember that you will need to call `approve()` from the `Balloons.sol` contract approving the DEX to handle a specific number of your $BAL tokens. To keep things simple, you can just do that when interacting with the UI or debug tab with your contract.

-    💧 Deposit liquidity, and then check your liquidity amount through the mapping in the debug tab. Has it changed properly? Did the right amount of assets get deposited?
-    🧐 What happens if you `deposit()` at the beginning of the deployed contract, then another user starts swapping out for most of the balloons, and then you try to withdraw your position as a liquidity provider? Answer: you should get the amount of liquidity proportional to the ratio of assets within the isolated liquidity pool. It will not be 1:1

---

### 🥅 Extra Challenge:

- [ ] `approve()` event emission: can you implement this into the event tabs so that it is clear when `approve()` from the `Balloons.sol` contract has been executed?
