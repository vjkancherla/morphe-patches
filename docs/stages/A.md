# Stage A - Baseline and the riskiest assumption

## What works now

With *Hide feeds* on, Reddit's five feed screens cannot draw anything on any route, and the
app works end-to-end as a guest with no login: a cold start opens Reddit's search page by
itself; every tap of the bar's Home opens search again; backing out lists no feed at any
moment; Morphe settings are reachable from the Communities top bar's menu; and a searched
subreddit opens and Backs back to search. With the switch off the app is stock.

## Steps

- S0 - the toolchain gate (no step summary; see scripts/checks/S00.sh and evidence/S00.log)
- [S1 - no feed renders; cold start lands on search; every Home tap opens search](../steps/S01.md)

## Checks

`scripts/checkpoint.sh 0` - 8 of 8 passed (evidence/S00.log). `scripts/checkpoint.sh 1` -
18 of 18 passed (evidence/S01.log, this session: S01 rewritten for the third amendment and
install -r; a pass only worked on leftover state earlier builds of the check, and the
rewrite bounds that out).

## Checks that changed

- S1 2026-11-09 - the old S01 stopped checking the drawer route and the joined-subreddit
  row (the v1 drawer design was replaced; the v2 note covers both under the render guards
  and the search landing). Log entry: "LOOSENED: S1 no longer checks..." in the plan's
  Changes log.
- S1 2026-11-10 - rewritten wholesale to the owner's third-amendment spec (hooks 5-6):
  nothing proves less than S01's previous form; the same rows gained the Home-tap flow
  and the guest-search flow.

## Plan changes

- Third amendment (2026-11-09): cold start opens search by itself via hook 5 at the
  guarded `HomePagerScreen`'s attach; every Home tap opens search via hook 6 at the bar's
  tap handler; one shared debounced search launch; a *Hide Inbox button* toggle; and the
  search zero state's Trending sections removed when the toggle is on. S01 rewritten,
  coverage rows V18-V20 added.
- The zero-state hook moved from the hydrate method to the repository's terminal
  publisher: the hydrate method's five-parameter shape is beyond the inline smali
  compiler (it emits nothing for it - reproduced), and the same flow ends at the terminal
  publisher (2026-11-10, in the S1 green commit).
- Device facts amended into the design note: backing out of the cold-start search does
  NOT show the Communities top bar; the top bar arrives through the Home-tap flow
  (measured, 2026-11-10).

## Different from the design

- The design note originally promised the Communities top bar after backing out of the
  cold-start search; the device disagrees and the note's "Behaviour to expect" was
  rewritten to the measured behavior. S01 asserts the top bar only where it is true.
- The zero-state filter is data-side at the terminal publisher (see plan changes); the
  design section was rewritten to match. The filter's device proof (V20) is S3's row.

## For you to decide

- Nothing inside Stage A. (S3's V20 outcome is a Stage B question, not covered here.)

## Review

Different model, new session:

    Read and follow docs/REVIEW-PROMPT.md for 101422f0d^..0e977c13c
