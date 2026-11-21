# 0001. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
BuckleUp Quiz will be built in stages (see [STAGES.md](../STAGES.md)), probably with long gaps
between them and possibly by different people or AI assistants. The reasons behind choices
(why no backend, why this audio mode) are easily lost.

## Decision
Keep lightweight Architecture Decision Records (Michael Nygard's format) in `docs/adr/`,
numbered sequentially. Accepted ADRs are not edited except for typos or status. A changed
decision gets a new ADR that supersedes the old one.

## Consequences
- Anyone can see *why* the code looks the way it does.
- Pull requests that make a structural decision should add an ADR (the PR template asks).
