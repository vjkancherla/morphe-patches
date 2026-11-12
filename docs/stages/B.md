# Stage B - The mechanism, on the device

## What works now

The feature is proven on the phone end to end with *Hide feeds* ON as a guest: the setting
OFF is stock, ON never renders a feed on any route the checks can drive (cold start,
Home taps and re-taps, external `r/` and root links, backgrounding and resuming,
rotation, the Popular row, Communities re-tap), the bottom bar stays usable and
configurable (*Hide Create* and *Hide Inbox* toggles round-trip and restore), the top bar
and its search button work, Morphe settings stay reachable, and logcat is clean of hook
failures and crashes across the whole gauntlet.

## Steps

- [S2 - cold start lands on search; tapping Home reaches the empty start screen](../steps/S02.md)
- [S3 - the device gauntlet: every remaining coverage row on the phone](../steps/S03.md)

## Checks

`scripts/checkpoint.sh 2` - 13 of 13 passed (evidence/S02.log). `scripts/checkpoint.sh 3` -
**20 of 21 passed** (evidence/S03.log): the one failure is V20, red **by the owner's
decision (accept as shipped, 2026-11-10)**, recorded in `docs/build-plan.md` - the
zero-state filter's one permitted attempt did not remove the Trending sections; the row
stays red with the reason.

## Checks that changed

- S03 - V7 and V14 strengthened (2026-11-10, no product code): the ColorOS sheet
  dismissal is verified gone with a require-Reddit-in-front rule, the top-bar search tap
  targets the real `search on Reddit` pill and fails loudly on no match, and V14's state
  chain is re-established (cold start, polled search page, explicit Back failure) before
  the bar dump is read. Nothing proves less than the previous form - each fix made a
  silent no-op or a stale dump fail loudly instead.
- S03 - V20 untouched: the failing check is neither loosened nor removed; it stands as
  the honest record of the accepted limitation.

## Plan changes

- 2026-11-10 - The owner called V20: option (a), accept as shipped (Changes log in
  `docs/build-plan.md` carries the full entry).
- 2026-11-10 - The S3 harness lessons (sheet timing, pill label, state chains) are in the
  step summary; the design note needed no further amendment - the product behaves as the
  third amendment describes except for the accepted V20 gap.

## Different from the design

- The design's zero-state section promised no Trending sections in the pre-typing search
  page; the device shows they still render. The hook is exactly where the design says
  (verified matched, injected, read-back verified) - the data-side filter never sees the
  models the page renders. Accepted by the owner; the design note keeps its promise, the
  product's known limitation is recorded here and in the plan.

## For you to decide

- How the final gate's `scripts/checkpoint.sh all` should treat the red-accepted V20 row
  (it fails and that is correct - does the gate absorb the one red row, or run with it?).
- The reviews still deferred (stage A's report and now this stage's); revive via
  `docs/REVIEW-PROMPT.md` whenever.
- The `.opencode/rules/hide-home-feed.md` pending edit (commit or discard) and its stray
  stage-template line, which only the owner may strike.

## Review

Different model, new session:

    Read and follow docs/REVIEW-PROMPT.md for cd970c9cf^..2fc99a379
    (the ^ includes the stage's first commit itself)
