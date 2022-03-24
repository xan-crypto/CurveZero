# CurveZero - Fixed rate USD loan protocol

**The CurveZero living litepaper**: 
https://docs.google.com/document/d/1rrYC32w63FzzV61rJWqqYomEMgfZ3cRR1jOlJmnnxeY

**The why**: A few years back a friend of ours walked into a bank, and walked out with a 18.5% fixed rate car loan. We asked him at the time why he accepted that rate. He responded that the bank said that was the price and that he also wanted a fixed rate. Unfortunately our friend wasn't financially savvy enough to know that the right rate was probably 8-10% at the time. We come from a country where the banks are not always honest actors. This protocol exists to solve that problem.

**What success looks like**: If successful, we would have created a fair and transparent USD fixed rate loan market. Where anyone, regardless if you live in the USA or Nigeria, whether you black or white, will be able to access fairly priced USD loans provided they have good quality collateral. This is a loan market that would be free from human bias and one where the growing value of trapped crypto collateral could be unlocked. Our goal is to reach a cumulative 1 Trillion USD in loans by 2030.

**Abstract**: This litepaper introduces a framework for determining the USD funding rate term structure. The protocol will live on-chain via layer 2 ethereum, either on starknet or zksync. The traditional bootstrap process for curve building is tricky due to the lack of liquid on-chain financial instruments from which rates can be extracted. The various shapes and kinks in term structure are also difficult to capture via a closed form solution, thus we rely on market forces for its expression. Effectively once this curve is known, a user can lock into a fixed rate loan for n months in a trustless and transparent manner (0-24 months initially).

**Protocol Architecture**:
![image](https://user-images.githubusercontent.com/62293102/153413152-6fad8e98-5e6f-4e28-b8a1-9661fc617d1d.png)

**Progress**:<br>
Protocol (cairo) - 65%<br>
Services (python) - 25%<br>
Website design - 10%<br>
Website integration - 10%<br>
Community building - 10%<br>
Audits - 0%<br>

**Key Dates**:<br>
04 Feb 2022 - First contract deployed on StarkNet Goerli test net<br>
16 Feb 2022 - First loan created and accrued compound interest correctly valued<br>
05 Mar 2022 - Lend borrow functional, including token transfers, PP price validation and dummy price oracles<br>
12 Mar 2022 - First loan liquidation and insurance fund payout working as expected<br>
18 Mar 2022 - Crypto native USD yield curve stripped from Defi/Futures/Treasury Bonds<br>
![image](https://user-images.githubusercontent.com/62293102/158979980-92401fe5-a91c-4337-9f1b-38bd4be9b2d6.png)

**Our Mantras**:<br>
Make the protocol better<br>
Keep the protocol secure<br>
Work together as a community<br>
