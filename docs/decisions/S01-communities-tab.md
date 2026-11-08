# Decision needed - S1 cannot tap Communities on this phone

Date: 2026-11-08. Branch `feat/hide-home-feed`. S1's code is committed; the device half is
blocked on the question below.

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

## Already proved / not proved

- Proved on the machine: build green; patch 29/29 with zero failed (all five guard
  fingerprints matched); guards present at instruction 0000 of each feed render method;
  hook 4 present at the Communities attach entry with the real view.
- Proved on the phone: *Hide feeds* can be turned on as a guest (no login); with it ON, the
  Home feed does not render (blank page, no feed markers in the dump).
- Not proved: the search page opens, Back returns to the empty Communities tab, no feed on
  the other V16 routes. The phone also re-locked within about a minute, so it needs to stay
  unlocked for the next device run.

## What the owner needs to do

1. Review this note and pick A, B or C.
2. Unlock the phone and keep it awake for the run (the screen re-locks quickly).
