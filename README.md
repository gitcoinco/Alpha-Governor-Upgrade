# Gitcoin Governor Bravo

An upgrade to a "Bravo" compatible Governor for the GitcoinDAO, built using the OpenZeppelin implementation.

## Development

### Foundry

This project uses [Foundry](https://github.com/foundry-rs/foundry). Follow [these instructions](https://github.com/foundry-rs/foundry#installation) to install it.


#### Getting started

Clone the repo

```bash
git clone git@github.com:gitcoinco/2022-Governor-upgrade.git
cd 2022-Governor-upgrade
```

Copy the `.env.template` file and populate it with values

```bash
cp .env.template .env
# Open the .env file and add your values
```

```bash
forge install
forge build
forge test
```

### Formatting

Formatting is done via [scopelint](https://github.com/ScopeLift/scopelint). To install scopelint, run:

```bash
cargo install scopelint
```

#### Apply formatting

```bash
scopelint fmt
```

#### Check formatting

```bash
scopelint check
```

## Scripts

 * `script/Deploy.s.sol` - Deploys the GitcoinGovernor contract
 * `script/Propose.s.sol` - Submits a proposal to the existing Gitcoin Governor Alpha proposing migration to the GitcoinGovernor. Must be executed by someone with sufficient GTC delegation.

 To test these scripts locally, start a local fork with anvil:

 ```bash
 anvil --fork-url YOUR_RPC_URL --fork-block-number 15980096
 ```

 Then execute the deploy script.

 _NOTE_: You must populate the `DEPLOYER_PRIVATE_KEY` in your `.env` file for this to work.

 ```bash
 forge script script/Deploy.s.sol --tc DeployScript --rpc-url http://localhost:8545 --broadcast
 ```

 Pull the contract address for the new Governor from the deploy script address, then execute the Proposal script.

 _NOTE_: You must populate the `PROPOSER_PRIVATE_KEY` in your `.env` file for this to work. Additionally, the
 private key must correspond to the `proposer` address defined in the `Proposal.s.sol` script. You can update this
 variable to an address you control, however the proposal itself will still revert in this case, unless you provide
 the private key of an address that has sufficient GTC Token delegation to have the right to submit a proposal.

 ```bash
forge script script/Propose.s.sol --sig "run(address)" NEW_GOVERNOR_ADDRESS --rpc-url http://localhost:8545 --broadcast
 ```

## License

The code in this repository is licensed under the [GNU Affero General Public License](LICENSE) unless otherwise indicated.

Copyright (C) 2022 Gitcoin Core
