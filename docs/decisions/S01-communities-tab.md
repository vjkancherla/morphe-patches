# Decision - S1 cannot tap Communities on this phone [RESOLVED 2026-11-09]

Date: 2026-11-08. Branch `feat/hide-home-feed`. S1's code is committed; the device half is
blocked on the question below.

**Resolved.** The owner picked Option A with one amendment (2026-11-09):

- Hook 1 (`getStartTab`, Home -> Communities) moves into S1. Cold start then opens the
  Communities screen, which launches search, and S1 is re-run as a cold-start check with
  no tap on a Communities tab.
- **The Home button stays in the bar.** On this phone the bar has no Communities slot, so
  hiding Home would leave Create, Inbox and You with no button back to the start screen.
  The feed guard already keeps Home blank; once hooks 2-3 land, tapping Home goes through
  hook 3 to the empty Communities screen with its search button.
- The Communities slot is remote-controlled and can come back, so every check must pass
  with or without a Communities tab.

## What was observed

With the patched build installed and *Hide feeds* ON as a guest, a cold start shows a blank
Home page (the Home feed guard works) and a bottom bar with four tabs:

    Home | Create | Inbox | You

There is no Communities tab. The bar builder (`jn90.a`) builds five slots but sets the
Communities/Answers slot to `null` when `hv2.d()` is true, which is the case on this phone.
That is v1's failure mode 4: the server emptied the Communities slot.

## Why this blocks S1

S1 is redefined as "tapping Communities opens the search page". The search launch is wired to
the Communities tab attaching. With no Communities tab in the bar, there is no way to make
it attach in S1: hooks 1-3 (the start-tab replacement) are the only existing route, and v2
puts them in S2.

The app therefore opens on a blank Home page, not search, until hook 1 is added.

## Options

| Option | What it means | Cost / risk |
|---|---|---|
| **A. Move hook 1 into S1** (recommended) | Add the start-tab replacement (`getStartTab`: Home -> Communities) now. Cold start then opens the Communities screen, which launches search. S1 proves the real landing on this phone; S2 finishes hooks 2-3 and the Home-tab hide. | Small reorder of the plan. Contradicts v2's sentence "hooks 1-3 land in S2", but not the feature design. One new fingerprint (hook 1) enters S1. |
| **B. Keep S1 as written** | Wait until a Communities tab route exists. No further progress on this device. | S1 stays red; S2/S3 do not start. |
| **C. Redefine S1 without search** | S1 proves only the five feed guards and the guest toggle; the search landing moves wholly to S2. | `LOOSENED:` S1 no longer proves the requirement it was redefined to prove. |

## Recommendation

Option A. It is the design's own mechanism (hooks 1-3), just moved one step earlier because
this phone has no Communities button to tap. It also proves the search link on the device
before more code is built on it.

## Already proved / not proved (matched to evidence/S01.log, 2026-11-09 run)

- Proved and recorded in the fresh S01 log: build green; patch applies with no failed patch -
  the result-file check now carries the "guard at instruction 0000" proof, because the patch
  re-verified every injected call at instruction index 0 after injecting (five feed guards plus
  hook 1). The same run's Home-button check records the bar.
- Done by hand in this session, not recorded by any checkpoint check: *Hide feeds* was turned
  ON as a guest (Morphe settings reached through the left drawer's *Morphe* entry as a guest -
  the note's open question is answered "yes"). The checkpoint's back-up evidence for the
  setting being ON is that the feed guard ran (blank Home, no feed markers).
- Proved on the phone during the re-run: cold start with hook 1 shows a blank page with no
  feed markers and the Home button still in the bar, and the app runs with no crash (log-clean
  check). A guest search shows no login prompt.
- **Not proved - stop condition:** the redirected Communities screen never attaches on cold
  start. Temporary morphe-debug logs (removed afterwards) showed `getStartTab` called with
  `Home` and returning `Communities`, but the Communities tab's attach (`L3`, hook 4) never
  ran, so the search link never fired; the screen stays a chrome-less blank page with the bar
  (Home Create Inbox You). This is on a boot whose Communities bar slot is empty
  (server-controlled). No workaround attempted, per the owner's stop rule.
- 2026-11-09, after hooks 2-3 (S2) landed: the cold start still does not attach. But tapping
  the bar's Home button - hook 3's selection funnel - **opened the search page on the first
  tap** (once per process), and the app is usable from there. So hooks 3+4 and the search link
  all work through the normal selection pipeline; only the initial cold-start screen install
  does not attach. Reverse-engineering during the report (not a fix attempt) found the v1
  trace's weak spot: `BottomNavScreen`'s stack change listener (`bottomnav/b.java`) derives
  the highlighted tab from whichever screen the stack shows, and the initial visible screen
  is not chosen by hook 1's `I5` push - the funnel the bar taps use, not the install call,
  attaches the tab screens. The no-feed guarantee held the whole time: every route stayed
  blank, and v2's priority ("a blank page is always an acceptable outcome") is satisfied.
- Proved standalone, by sending the search link with `am start`: the search page opens as a
  guest with no login prompt and no vote/comment markers. Its zero state before typing shows
  a *Trending* list (trending searches and trending communities) - the owner's-eyes question,
  screenshot at `evidence/S01-search-zero-state.png`. The keyboard opens automatically
  (cosmetic, answered).
- Not proved: tapping Home reaching the empty start screen (hooks 2-3, S2); the rest of V16.
- The phone re-locks within about a minute; it needs to stay unlocked for device runs.

## What the owner needs to do

~~1. Review this note and pick A, B or C.~~
~~2. Unlock the phone and keep it awake for the run (the screen re-locks quickly).
   After a fresh install: turn *Hide feeds* ON as a guest, then re-run.~~

3. Decide the follow-up to the stop condition (see "Not proved"):
   - **A. Accept the one-tap landing** - cold start is blank and feed-free (v2's priority:
     "a blank page is always an acceptable outcome"); tapping the bar's Home button opens
     search once per process, and everything after that works. S2's checks would assert that
     flow (`LOOSENED:` - V5's cold start no longer opens search by itself).
   - **B. One more tracing pass at the real cold-start selection site** - a new fingerprint
     where the stack's initial screen is actually chosen (not the `I5` push v1 traced). Two
     fix attempts already ran on this check; the third would be fresh design work.
