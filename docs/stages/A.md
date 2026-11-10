# Stage A - Baseline and the riskiest assumption

## What works now

With *Hide feeds* on, Reddit's five feed screens cannot draw anything on any route, and the
app works end to end as a guest with no login: a cold start opens Reddit's search page by
itself, every tap of the bar's Home opens search again, backing out never lists a feed, and
Morphe settings stay reachable from the Communities top bar's menu. With the switch off the
app is stock.

## Steps

- S0 - toolchain gate (no step summary; see `scripts/checks/S00.sh`)
- [S1 - no feed renders; cold start lands on search; every Home tap opens search](../steps/S01.md)

## Checks

`scripts/checkpoint.sh 0` - 8 of 8 passed (evidence/S00.log). `scripts/checkpoint.sh 1` -
18 of 18 passed (evidence/S01.log).

## Checks that changed

- S1 - LOOSENED (2026-11-09): no longer checks the drawer route or the joined-subreddit
  row, because the v1 drawer design was replaced. Covered instead by: the five render
  guards and the search-landing rows.
- S1 - expanded (2026-11-10): rewritten to the third amendment's spec (hooks 5-6,
  install -r, no marker skip); nothing proves less than the previous form.

## Plan changes

- 2026-11-09 - Third amendment: cold start opens search by itself (hook 5 at the guarded
  `HomePagerScreen`'s attach), every Home tap opens search (hook 6 at the bar's tap
  handler), one shared debounced launch, a *Hide Inbox button* toggle, and the search zero
  state's Trending sections removed. S01 rewritten; coverage rows V18-V20 added.
- 2026-11-09 - Stale-build risk closed: every check installs the freshly patched build
  with `install -r` (data kept) - no marker-based skip.
- 2026-11-10 - The zero-state filter moved to the repository's terminal publisher: the
  patcher's inline smali compiler emits nothing for the hydrate method's five-parameter
  shape (reproduced); the design note's zero-state section rewritten to match.

## Different from the design

- The note's "Behaviour to expect" promised the Communities top bar after backing out of
  the cold-start search; the device measured the opposite (bar labels only for 30+ s) and
  the note was rewritten to the measured behavior. S01 asserts the top bar only where it
  is true.
- The design note pitted the zero-state hook at the hydrate method's entry before it moved
  (see plan changes); the code, note and evidence now agree on the terminal publisher.

## For you to decide

- Nothing. (S3's V20 one-shot outcome is a Stage B question, not covered here.)

## Review

Different model, new session:

    Read and follow docs/REVIEW-PROMPT.md for 101422f0d^..0e977c13c
    (the ^ includes the stage's first commit itself)
