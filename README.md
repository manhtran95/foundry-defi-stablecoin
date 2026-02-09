## Overview
This project implements a stablecoin named DSC and the vault system that builds around it.

## Stablecoin system details
### DSC characteristics
* Relative stability: pegged to $1.00
    1. Getting exchange rate via Chainlink price feed
    2. Set a function to exchange ETH & BTC -> $$
* Stability mechanism: algorithmic
    1. Enough collateral is required to minting
* Collateral type: Exogenous, collateralized by
    1. wETH
    2. wBTC

## Installation

## License
Foundry Defi Stablecoin is released under the MIT License.