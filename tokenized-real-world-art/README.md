# tokenized-real-World-art

## Overview
This Clarity smart contract enables fractional ownership of real-world art installations through NFTs (SIP-009 standard). It also automates profit distribution from exhibitions and rentals while integrating IoT sensors for condition and location tracking.

## Features
- **Fractional NFT Ownership**: Art pieces are divided into shares, allowing multiple owners.
- **Automated Profit Distribution**: Rental earnings are distributed to shareholders.
- **IoT Sensor Integration**: Approved oracles update artwork location and condition.
- **Secure Rental System**: Art pieces can be rented, and payments are stored in contract balance.
- **Owner-Only Privileges**: Contract owner manages NFT minting, pricing, and distribution.

## Data Structures
- `artworks`: Stores details about each artwork (name, shares, location, condition, rental price, balance).
- `nft-owners`: Maps NFT shares to owners.
- `shareholder-balances`: Tracks rental profit per owner.
- `iot-oracles`: Approved entities allowed to update artwork status.
- `art-created-event` & `profit-distributed-event`: Flags to track events.

## Functions
### **1. Create Artwork**
**`(define-public (create-artwork (artwork-id uint) (name (string-utf8 50)) (total-shares uint) (initial-location (string-ascii 100)))`**
- Contract owner initializes an artwork with its details.

### **2. Mint NFT Shares**
**`(define-public (mint-share (artwork-id uint) (recipient principal) (shares uint))`**
- Contract owner mints fractional shares for an artwork.

### **3. Update IoT Data**
**`(define-public (update-artwork-status (artwork-id uint) (location (string-ascii 100)) (condition (string-ascii 50)))`**
- Approved IoT oracles update the artwork’s condition and location.

### **4. Distribute Rental Profits**
**`(define-public (distribute-profits (artwork-id uint))`**
- Distributes rental revenue among shareholders.

### **5. Withdraw Profits**
**`(define-public (withdraw-profits)`**
- NFT shareholders withdraw accumulated profits.

### **6. Set Rental Price**
**`(define-public (set-rental-price (artwork-id uint) (price uint))`**
- Contract owner sets the rental price for an artwork.

### **7. Rent Artwork**
**`(define-public (rent-artwork (artwork-id uint))`**
- Users rent an artwork by paying the set price.

## Security Measures
- **Authorization Checks**: Restricted functions require contract ownership verification.
- **IoT Verification**: Only approved oracles can update artwork status.
- **Profit Handling**: Ensures correct distribution of rental earnings.
- **NFT Integrity**: Prevents over-minting of artwork shares.

## Deployment
- Deploy the contract using a Clarity-compatible blockchain such as Stacks.
- Assign the contract owner.
- Register approved IoT oracles for condition tracking.

## Future Enhancements
- Implement secondary NFT marketplace for trading shares.
- Enable dynamic pricing based on demand and condition.
- Introduce governance mechanisms for decentralized decision-making.

This contract enables a decentralized, transparent, and automated system for managing real-world art investments through blockchain technology.

