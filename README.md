# SmartCity Services

A blockchain-based urban service management platform built on Stacks using Clarity smart contracts.

## Overview

SmartCity Services is a decentralized platform that enables cities to offer token-gated service subscriptions to citizens. The platform facilitates service access management, usage tracking, and citizen engagement through a transparent and secure blockchain infrastructure.

## Features

- **Service Management**: Create and manage urban services with customizable parameters
- **Subscription System**: Token-gated access to city services with time-based subscriptions
- **Usage Tracking**: Monitor service utilization across the city
- **Citizen Engagement**: Enable citizens to interact with city services through a unified platform

## Smart Contract Architecture

The core of SmartCity Services is built on a Clarity smart contract that handles:

- Service registration and management
- Citizen subscription handling
- Service usage tracking
- Balance management for service payments

### Key Components

#### Data Structures

- **Services Map**: Stores service details including name, description, price, provider, and status
- **Subscriptions Map**: Tracks citizen subscriptions with expiry dates and status
- **Usage Map**: Records service utilization by citizens
- **Balances Map**: Manages citizen token balances for service payments

#### Functions

##### Administrative Functions

- `add-service`: Register a new city service
- `update-service`: Modify existing service parameters

##### Citizen Functions

- `deposit`: Add funds to citizen balance
- `subscribe`: Purchase a subscription to a city service
- `use-service`: Access a subscribed service and record usage

##### Read-Only Functions

- `get-service`: Retrieve service details
- `get-subscription`: Check subscription status
- `get-service-usage`: View service utilization metrics
- `get-balance`: Check citizen balance
- `is-subscription-active`: Verify if a subscription is valid
- `get-all-services`: List all available services

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Clarity development environment
- [Stacks Wallet](https://www.hiro.so/wallet) - For interacting with the deployed contract

### Installation

1. Clone the repository:
   ```
   git clone https://github.com/wonderlandalex6/SmartCity-Services.git
   cd SmartCity-Services
   ```

2. Install dependencies:
   ```
   npm install
   ```

3. Run Clarinet console for local testing:
   ```
   clarinet console
   ```

### Usage Examples

#### Adding a new service (admin only)
```clarity
(contract-call? .SmartCity-Services add-service "Public Transport" "City-wide transportation services" u100 tx-sender)
```

#### Depositing funds
```clarity
(contract-call? .SmartCity-Services deposit u500)
```

#### Subscribing to a service
```clarity
(contract-call? .SmartCity-Services subscribe u0)
```

#### Using a service
```clarity
(contract-call? .SmartCity-Services use-service u0)
```

## Use Cases

- **Public Transportation**: Token-gated access to buses, trains, and bike-sharing
- **Utility Services**: Management of water, electricity, and waste services
- **Public Facilities**: Access to libraries, museums, and recreational centers
- **Citizen Participation**: Voting and engagement in city governance

## Future Enhancements

- Integration with IoT devices for automated service access
- Reputation system for service providers
- Citizen feedback and rating mechanism
- Multi-tiered subscription levels
- Cross-city service interoperability

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact

For questions or support, please open an issue on the GitHub repository.
