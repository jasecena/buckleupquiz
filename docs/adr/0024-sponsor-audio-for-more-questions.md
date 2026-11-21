# 0024. More free questions for listening to a sponsor message

- **Status:** Proposed (product idea, 2026-11-22; not built)
- **Date:** 2026-11-22
- **Relates to:** [ADR-0022](0022-free-allowance-packs-and-basic-subscription.md) (allowance), [ADR-0004](0004-privacy-no-network-no-sdks.md) (no third-party SDKs), [ADR-0021](0021-aws-infrastructure-terraform.md) (CDN)

## Context
Product idea: free families could earn more questions by listening to audio ads suitable for
kids:
- listening raises the daily top-up from **2 to 5 new questions per topic**;
- each extra ad adds **2 more questions**.

## Constraints
- **App Store Kids Category (Guidelines 1.3, 5.1.4):** no third-party advertising, except in
  limited cases of *contextual* ads from services with public Kids Category policies and
  **human review of every ad creative**. No IDFA, no device or location data, no tracking.
- **Children's advertising rules:** the AANA Code for Advertising & Marketing Communications to
  Children (Australia), and COPPA and CARU (US). No pressure to buy, no "ask your parents",
  nothing that blurs ads and content.
- **ADR-0004:** no third-party runtime SDKs. An ad network SDK would break the privacy label and
  the product's promise to parents.

## Proposed decision
**First-party sponsor audio, no ad network:**
- Short (15–30 s) family-friendly sponsor messages, chosen and **reviewed by us**. They're
  stored on our CDN like voice packs (`api.buckleupquiz.com/sponsors/…`). There's no SDK, no
  tracking, and no per-user targeting.
- They're contextual at most: the same message for everyone, or by topic. The app reports only
  anonymous play counts (for sponsor billing), on the error-report pipeline's terms (ADR-0020).
- **A parent opts in** behind the parental gate: "Earn more questions with sponsor messages".
  The messages play between games, never mid-question, and are clearly announced ("Here's a
  message from our sponsor").
- Rewards, as constants in `AllowanceStore`: with sponsor messages on, the daily top-up is
  **5** instead of 2; each extra message adds **2** questions, up to a daily cap.
- BuckleUp Basic never plays sponsor messages.

## Open questions
- Do we have sponsors? Without them, a house message (for example promoting Basic) could fill
  the slot. It must still be behind the parental gate and not aimed at kids.
- A legal and App Review check of the exact flow before building.
