# Staking Contract

## Usage
-----
### Install requirements with npm:

```shell
npm install
```

### Run all tests:

```shell
npx hardhat test
```

Report Gas:

```shell
REPORT_GAS=true npx hardhat test
```

### Deploy
Preparation:
- Set `NODE_URL` in `.env`
- Set `STAKE_TOKEN` in `.env`
- Set `REWARD_TOKEN` in `.env`
- Set `PRIVATE_KEY` in `.env`

```shell
npx hardhat run scripts/deploy.ts --network <network>
```
