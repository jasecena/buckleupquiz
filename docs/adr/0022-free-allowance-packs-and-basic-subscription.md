# 0022. Free allowance, question packs and the BuckleUp Basic subscription

- **Status:** Accepted (product owner's direction, 2026-11-22; numbers can be tuned)
- **Date:** 2026-11-22
- **Supersedes:** [ADR-0010](0010-storekit2-purchases.md) (one-off Family Pass)
- **Relates to:** [ADR-0016](0016-leitner-spaced-repetition.md) (reviews), [ADR-0004](0004-privacy-no-network-no-sdks.md) (no accounts)

## Context
Families can play for free, but parents pay for the things that matter: more fresh questions
(for long trips), and the educational values topics. The product owner's brief:
- Free play with a limited number of questions, plus 2 new questions per topic each day the
  app is opened. Manners is always available but limited ("so parents see the opportunity"),
  with no daily top-up.
- 50 questions for $0.99, one-off, remembered on the phone.
- A **Basic** monthly subscription at **A$4.99**, cancel anytime: 10 topics, fresh questions
  every day, fixing scores, and more later. Higher tiers later for longer trips.
- Every game is planned up front. If there aren't enough fresh questions, say so before
  starting. 0–2 each: don't start. 3–4: warn, then play. 5 each is the minimum game.

## Decision

### What a question costs
A question costs **one, once**: the first time anyone in the family hears it. Reviews, repeats,
anything already heard, and Talk About prompts are always free. Spaced repetition (ADR-0016) is
never paywalled, because it's how children learn. `FreshBudget` (QuizCore) carries what a game
may spend. `AllowanceStore` (app) keeps the family's heard-question set and balances, and
charges what was actually asked when a game ends.

### Plans
| | Free | Question pack | **BuckleUp Basic** |
|---|---|---|---|
| Price | $0 | **A$0.99**, one-off (consumable) | **A$4.99 / month**, cancel anytime |
| Topics | Animals, Geography (free knowledge topics) + Manners & Friendship | — | **All 10** (every topic with content) |
| New questions | **30** per free knowledge topic + **2 more each day the app is opened**; Manners **10**, no top-up | **+50**, any topic you can open, never expire | **40 a day**, any topic (packs add on top) |
| Players per game | 2 | — | 6 |
| Fix scores after a game | — | — | ✓ |
| Reviews of questions already heard | free | free | free |

Higher tiers (for example "Plus" with more questions a day for long trips) come later, in the
same subscription group so families can move between them.

### Games are planned before they start
`QuizSession` plans every turn when it's created. Players take turns in order, the review mix
(ADR-0016) applies, nothing repeats in a day, and the budget is spent. If a round can't be
completed for everyone, it's dropped, so **every player gets the same number**. Length is
**questions each**: 5, 10 or 15, and never more than **50 questions in one game** (no Endless mode, product decision 2026-11-22). Before starting, Home checks `plannedEach`:
- equals what was asked, or ≥ 5 → start;
- **3–4** → "Almost out of questions for today: N each left". Play N each / Get more questions /
  Not now;
- **0–2** → "You're out of questions for today. New questions come back tomorrow, or get more
  now". OK / Get more questions. **The game doesn't start.**

Play (random topic) picks a topic with a full game left today, else the one with the most.

### Purchases
- StoreKit 2. Products: `com.jcena.buckleupquiz.basic.monthly` (auto-renewable, group
  "BuckleUp Quiz") and `com.jcena.buckleupquiz.questions50` (consumable).
- Pack credits are kept on the phone (`AllowanceStore`, each transaction credited once). A
  consumable can't be restored by the App Store, so moving these to iCloud key-value storage is
  a follow-up.
- The subscription comes from `Transaction.currentEntitlements` (restorable, Family Sharing
  can be enabled in App Store Connect).
- Every purchase screen sits behind the **parental gate** (a two-digit × one-digit sum;
  Kids Category, App Review 1.3). The paywall shows the price from the App Store,
  "cancel anytime", Restore, Terms of Use and the Privacy Policy (required for subscriptions).
- TestFlight builds keep a "BuckleUp Basic (testing)" switch until sandbox products are live.

## Alternatives considered
- **One-off Family Pass (ADR-0010)**: simple, but it doesn't pay for an ongoing flow of new
  content, and the product owner wants a subscription.
- **Hard limit on games per day**: frustrating. Limiting *new* questions keeps reviews (the
  learning) free and the app always playable.
- **Ads**: not allowed in the Kids Category, and against ADR-0004.

## Consequences
- App Store Connect needs the two products (prices, descriptions, a review screenshot) and the
  **Paid Applications agreement** (banking and tax) signed by the account holder before sandbox
  purchases work.
- The App Store listing must describe the subscription. The privacy label is unchanged:
  purchases are handled by Apple and nothing is linked to the user.
- Content volume now drives revenue: each topic needs well over 30 questions per band to make
  Basic's 40 a day meaningful (M7).
- Numbers live as constants in `AllowanceStore` and `EntitlementStore`, so tuning them is a
  one-line change plus this ADR.
