# Squad game

-game
  -
  -
-tec
  - [Getting Started](#getting-started)
    - [Requirements](#requirements)
    - [Quickstart](#quickstart)
    - [Testing](#testing)
  - [Deploying to a network](#deploying-to-a-network)
    - [Setup](#setup)
    - [Deploying](#deploying)
      - [Working with a local network](#working-with-a-local-network)
      - [Working with other chains](#working-with-other-chains)
  - [Security](#security)
  - [Contributing](#contributing)


# Attributes

- Strength: Determines physical power and ability to carry heavy loads.
- Endurance: Reflects stamina and resistance to fatigue during prolonged activities.
- Acrobatics: Influences circus-worthy acrobatics, making the player a nimble ninja in the wilderness.
- Brainiac: Governs their nerdy intelligence, ability to invent quirky gadgets, and useless trivia knowledge.
- Perception: Affects awareness, alertness, and the ability to detect subtle details in the environment.
- Zen-Fu: Represents inner peace and mindfulness, helping the player stay calm in the face of chaotic survival situations.
- Dexterity: Governs hand-eye coordination, fine motor skills, and overall precision in movement.
- Charm-o-Meter: Measures the player's charisma, enchanting both humans and woodland creatures alike.
- Adapt-o-matic: Reflects their shape-shifting skills, turning adversity into opportunities with a dash of humor.
- Karma: Reflects the player's cosmic balance, influencing the consequences of their actions and the universe's response.



Taiko: round.


# Getting Started

## Requirements

Please install the following:

-   [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)  
    -   You'll know you've done it right if you can run `git --version`
-   [Foundry / Foundryup](https://github.com/gakonst/foundry)
    -   This will install `forge`, `cast`, and `anvil`
    -   You can test you've installed them right by running `forge --version` and get an output like: `forge 0.2.0 (f016135 2022-07-04T00:15:02.930499Z)`
    -   To get the latest of each, just run `foundryup`

And you probably already have `make` installed... but if not [try looking here.](https://askubuntu.com/questions/161104/how-do-i-install-make)

## Quickstart

```sh
git clone https://github.com/jpgonzalezra/squad-game
cd squad-game
make # This installs the project's dependencies.
make test
```

## Testing

```
make test
```

or

```
forge test
```

# Deploying to a network

Deploying to a network uses the [foundry scripting system](https://book.getfoundry.sh/tutorials/solidity-scripting.html), where you write your deploy scripts in solidity!

## Setup

We'll demo using the Sepolia testnet. (Go here for [testnet sepolia ETH](https://faucets.chain.link/).)

You'll need to add the following variables to a `.env` file:

-   `SEPOLIA_RPC_URL`: A URL to connect to the blockchain. You can get one for free from [Infura](https://www.infura.io/) account
-   `PRIVATE_KEY`: A private key from your wallet. You can get a private key from a new [Metamask](https://metamask.io/) account
    -   Additionally, if you want to deploy to a testnet, you'll need test ETH and/or LINK. You can get them from [faucets.chain.link](https://faucets.chain.link/).
-   Optional `ETHERSCAN_API_KEY`: If you want to verify on etherscan

## Deploying

```
make deploy-sepolia contract=<CONTRACT_NAME>
```

For example:

```
make deploy-sepolia contract=LucidSwirl
```

This will run the forge script, the script it's running is:

```
@forge script script/${contract}.s.sol:Deploy${contract} --rpc-url ${SEPOLIA_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY}  -vvvv
```

If you don't have an `ETHERSCAN_API_KEY`, you can also just run:

```
@forge script script/${contract}.s.sol:Deploy${contract} --rpc-url ${SEPOLIA_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast 
```

These pull from the files in the `script` folder. 

### Working with a local network

Foundry comes with local network [anvil](https://book.getfoundry.sh/anvil/index.html) baked in, and allows us to deploy to our local network for quick testing locally. 

To start a local network run:

```
make anvil
```

This will spin up a local blockchain with a determined private key, so you can use the same private key each time. 

Then, you can deploy to it with:

```
make deploy-anvil contract=<CONTRACT_NAME>
```

Similar to `deploy-sepolia`

### Working with other chains

To add a chain, you'd just need to make a new entry in the `Makefile`, and replace `<YOUR_CHAIN>` with whatever your chain's information is. 

```
deploy-<YOUR_CHAIN> :; @forge script script/${contract}.s.sol:Deploy${contract} --rpc-url ${<YOUR_CHAIN>_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast -vvvv

```

# Security

This framework comes with slither parameters, a popular security framework from [Trail of Bits](https://www.trailofbits.com/). To use slither, you'll first need to [install python](https://www.python.org/downloads/) and [install slither](https://github.com/crytic/slither#how-to-install).

Then, you can run:

```
make slither
```

And get your slither output. 



# Contributing

Contributions are always welcome! Open a PR or an issue!
