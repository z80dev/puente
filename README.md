# Puente

puente is a protocol for token exchanges across different chains implemented in vyper. The idea is to leverage message relayers such as Layer Zero to communicate and execute transactions across various chains. the design philosophy is to embrace the necessary asynchronicity of secure cross-chain smart contract interactions, putting the weight of coordinating across chains on the 'taker' of the swap, who is in-turn being compensated via a swap fee. for the 'maker' who is placing orders there is no need to coordinate; they place an order on chain A, and eventually their desired tokens appear in their wallet on chain B.

## Project Overview

The primary component of this project is a smart contract called `Book`. The `Book` contract maintains a list of token orders. An order represents a user's intention to exchange a certain amount of one token for another. Each order contains details about the token to be exchanged, the desired token in return, and the quantities of each.

Each instance of the `Book` contract can be deployed on a separate chain and maintain its own list of orders. For exchanging tokens across different chains, the `Book` contracts communicate via message relayers. An order created on one `Book` (say Book A) can be filled by a user on a different `Book` (say Book B) on a different chain. 

## Features 

- **Order Addition:** Users can add orders to the order book specifying the details of the token exchange they wish to perform. Each order is assigned a unique nonce to identify the order.

- **Order Cancellation:** Users have the ability to cancel their orders if they are no longer interested in performing the token exchange.

- **Order Filling:** Any user, apart from the maker of the order, can fill an active order. Filling an order exchanges the specified amount of the maker's token for the specified amount of the desired token.

- **Cross-chain Order Filling:** A unique feature of this project is the ability to fill orders across different chains. A user on Book B can fill an order created on Book A. The two `Book` contracts communicate via message relayers to perform the cross-chain transaction.

- **Book Trust Mechanism:** Each `Book` maintains a list of other `Book` contracts that it trusts. This is to ensure that cross-chain transactions are performed only with verified `Book` contracts.

## Setup Instructions

If you would like to run the tests or use the contracts, please follow these steps:

1. Install `ape` using pip:

```bash
pip install eth-ape
```

2. Install the necessary plugins using `ape`:

```bash
ape plugins install .
```

3. Run the tests:

```bash
ape test
```

This should run all the tests in the test suite to ensure the contract is working as expected.

## Testing 

The test suite covers various aspects of the contract, including adding and canceling orders, filling orders, and filling orders across different `Book` instances. The tests are written in Python using `pytest` and `ape`.

## Future Work 

While the `Book` contract is designed for cross-chain transactions, currently all `Book` instances are on the same chain. In the future, we plan to deploy the `Book` instances on different chains and implement message relayers for cross-chain communication. This will enable truly decentralized and cross-chain token exchanges. 

## Contributing

We welcome contributions! Feel free to open an issue or submit a pull request if you would like to improve this project. 

## License

This project is licensed under the terms of the MIT license.
