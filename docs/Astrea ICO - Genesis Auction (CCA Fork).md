### **Astrea Genesis Auction (CCA Fork)**

## **Executive Summary**

### **Overview**

Astrea will launch its genesis token distribution using a fork of Uniswap’s Continuous Clearing Auction (CCA) on Ethereum Mainnet.

The goal is to enable transparent market-driven price discovery while minimizing smart contract risk and avoiding the shortcomings of traditional ICOs.

Unlike a fixed-price token sale, the auction allows the market to determine Astrea’s initial valuation through open participation over a 7-day period.

The ASTREA token is required for network operation, including validators, provers, fees, and future ecosystem incentives. The auction is intended to determine initial distribution and treasury funding, not whether the network launches.

---

## **Objectives**

### **Primary Goals**

* Fair and transparent token distribution
* Market-discovered valuation
* Raise treasury capital for network launch
* Broad community ownership
* Minimal modifications to audited smart contracts
* Avoid first-come-first-serve ICO dynamics
* Create a memorable genesis event for the ecosystem

### **Secondary Goals**

* Generate community engagement
* Attract validators, provers, and ecosystem participants
* Establish an initial market reference price
* Create a historical genesis participation record

---

## **Proposed Auction Parameters**

| Parameter | Value |
| ----- | ----- |
| Network | Ethereum Mainnet |
| Auction Mechanism | Forked Uniswap CCA |
| Duration | 7 Days |
| Token Allocation | 10% of Total Supply |
| Accepted Asset | ETH |
| Target FDV Range | $30M–50M |
| Maximum FDV | $100M (TBD) |
| Minimum FDV | None or Very Low Threshold |
| LP Migration | Disabled |
| NFT Participation Receipt | Deferred to later contract |

---

##

## **How It Works**

* Participants deposit ETH into the auction over a seven-day period.
* As demand accumulates, the implied valuation of the network updates continuously.

Assuming 10% of supply is sold:

| Total Demand | Implied FDV |
| ----- | ----- |
| $1M | $10M |
| $3M | $30M |
| $5M | $50M |
| $10M | $100M |

At auction completion:

* The final clearing price is calculated.
* All participants receive ASTREA at the same effective clearing price.
* v1 does not implement an onchain FDV cap; any future cap should be a separate scoped change.
* Users claim ASTREA through a claim portal.

---

## **Recommended Philosophy**

### **No Meaningful Failure Condition**

The network will launch regardless of auction outcome.

Therefore, the auction should not determine whether Astrea exists.

Instead, it should determine:

* Initial token distribution
* Treasury funding
* Market valuation

A meaningful minimum raise threshold introduces unnecessary launch risk and negative optics.

v1 recommendation:

* No minimum threshold.
* `requiredCurrencyRaised = 0`.

---

## **Anchor Commitments**

Prior to launch, Astrea should secure commitments from:

* Strategic investors
* Ecosystem supporters
* Advisors
* Community leaders

Target:

### **$1M of anchor demand**

Benefits:

* Strong Day 1 auction metrics
* Better social proof
* Reduced risk of weak early signaling
* More stable price discovery

---

## **Liquidity Strategy**

The auction should not automatically create a liquidity pool.

Benefits:

* Simpler implementation
* Treasury flexibility
* Reduced launch complexity
* Ability to make a deliberate liquidity decision post-auction

Liquidity can be:

* Seeded manually
* Managed through a market maker
* Introduced alongside network launch

---

## **NFT Participation Receipt**

The Genesis Participation NFT is deferred from v1 and should be implemented as a separate contract.

Potential utility includes:

* Proof of participation
* Governance recognition
* Future ecosystem rewards
* Testnet and mainnet incentives
* Historical provenance

This NFT should not modify core auction logic. A later implementation can read settled bid state and mint proof of participation after the auction.

The ERC-1155 validation hooks retained in this fork are not receipt NFTs. They are optional pre-bid gating hooks that can require an address to already own a qualifying ERC-1155 token before bidding.

---

## **Success Criteria**

The Astrea Genesis Auction is considered successful if it:

* Distributes 10% of supply broadly
* Raises approximately $3M–10M
* Produces a market-discovered valuation
* Avoids launch failure scenarios
* Requires minimal modification of audited code
* Creates a strong foundation for validator, prover, and ecosystem growth

### **Proposed Launch Positioning**

The Astrea Genesis Auction is not a token sale.

It is the market’s opportunity to determine the initial ownership and valuation of the first proof-native computation network.
