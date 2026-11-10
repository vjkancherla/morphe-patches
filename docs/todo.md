# Hide Home Feed - Tracker

Design: [design/hide-home-feed-v2.md](design/hide-home-feed-v2.md) · Plan: [build-plan.md](build-plan.md)

## Stage A - Baseline and the riskiest assumption

- [x] [S0 - fork builds and patches 2026.45.0, unmodified](../scripts/checks/S00.sh)
- [ ] [S1 - no feed renders, cold start lands on search, every Home tap opens search](../scripts/checks/S01.sh)

## Stage B - The mechanism, on the device

- [ ] [S2 - cold start lands on search; tapping Home reaches the empty start screen](../scripts/checks/S02.sh)
- [ ] [S3 - the device gauntlet (incl. V12, V16 with/without a Communities tab, V19, V20)](../scripts/checks/S03.sh)

## Stage C - Wrap-up

- [ ] [S4 - final gate and hand-off report](../scripts/checks/S04.sh)
