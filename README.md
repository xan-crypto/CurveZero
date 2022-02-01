# CurveZero - Fixed rate USD loan protocol

The CurveZero whitepaper can be found here: https://docs.google.com/document/d/1rrYC32w63FzzV61rJWqqYomEMgfZ3cRR1jOlJmnnxeY/edit?usp=sharing

**What success looks like**: If successful, we would have created a fair and transparent USD fixed rate loan market. Where anyone, regardless if you live in the USA or Nigeria, whether you black or white, will be able to access fairly priced USD loans provided they have good quality collateral. This is a loan market that would be free from human bias and one where the growing value of trapped crypto collateral could be unlocked. Our goal is to reach a cumulative 1 Trillion USD in loans by 2030.

**Abstract**: This litepaper introduces a framework for determining the USD funding rate term structure. The protocol will live on-chain via layer 2 ethereum, either on starknet or zksync. The traditional bootstrap process for curve building is tricky due to the lack of liquid on-chain financial instruments from which rates can be extracted. The various shapes and kinks in term structure are also difficult to capture via a closed form solution, thus we rely on market forces for its expression. Effectively once this curve is known, a user can lock into a fixed rate loan for n months in a trustless and transparent manner (0-24 months initially).
