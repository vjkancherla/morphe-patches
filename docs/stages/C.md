# Stage C - Final gate and hand-off (2026-11-12)

The delivery session of the *Hide feeds* feature, closed out on the owner's word. This
report covers the credential-storm recovery (4a/4b), the final gate (S04), and the
hand-off state.

## The credential storm - what happened, and what fixed it

**The storm.** On 2026-11-12 mid-morning, after two clean days on identical product code,
every launch of `com.reddit.frontpage` was followed (~5 s) by a Google credential-chooser
sheet ("Sign-in options / Unlock sign-in options for Reddit") raised INTO Reddit's task by
the system on Reddit's own behalf (`mRealCallingUid=10598`). The owner never signs in, so
the sheet made the app unusable and poisoned the device checks.

**The investigation.** Nothing in the product code had changed (verified: the product tree
at the last known-good commit is byte-identical to the storming one). The earlier "hook 7"
attempt (skipping the welcome flow's credential query) did not stop the sheet and
hard-coded an R8 field name - reverted. A fresh install (data wiped) still fired the
sheet - so the wedged state was NOT Reddit's app data. Log tripwires injected at the
credential datasource then pinned the requester precisely: both launch-time asks came
through `RedditCredentialsDataSource`'s R8-moved body (`credentialsmanager/a;->f`, found
structurally - suspend-lambda shape plus datasource-unique strings, no obfuscated names),
and the system's `CredentialManager` log confirmed `callingPackage: com.reddit.frontpage`
with the Bitwarden and Google identity providers answering. Google-side per-app state,
keyed to the package identity and this fork's signing key, explains every observed fact:
the old install stormed, the fresh install (same key) stormed, the owner's separately
signed 2026.40.0 phone build did not. The root state is Google's, not Reddit's - so the
durable product fix is to never ask.

**4a - the ask is suppressed (commit 25f758fb1).** The datasource's entry now returns the
flow's OWN no-credential result: the same sealed wrapper its `NoCredentialException`
branch builds and returns. The new-instance / sget-object / invoke-direct references are
read off the method's own bytecode at patch time, anchored on the non-obfuscated
androidx `NoCredentialException` type-check; a missing piece fails the patch. Log-only
tripwires remain (`MorpheCred` tag: every ask logs its stack; suppressed asks log a
counted line). Verified: `failedPatches: []`, read-back of the injected entry exact, and
on-device `MorpheCred: credential request suppressed` at the datasource with the sheet
gone.

**4b - the welcome screen is gone (commit f61021043, owner-approved 2026-11-12).** With
the sheet gone, a fresh install then cold-started into `IntroductionActivity` (the
welcome/login flow) - and BACK from it exits the app, which made the reinstall settings
flow unreachable. Bytecode showed the decision: Reddit's forced-login gate
(`RedditForceLoginGate`, found structurally by its real `Session.isLoggedOut()` call)
returns true whenever there is no session plus server-side config, and routes every cold
start into the welcome flow on BOTH Hide-feeds states - before any home or feed logic,
bypassing the onboarding gate that `Start as guest` already forces true. Since this fork
has no sign-in surface at all, the owner approved forcing that gate to return false
(single choke point; its callers are the launch delegate and MainActivity). Guests keep
the app's own home, where the fork's start-tab hooks land them on search. Note: with
*Hide feeds* OFF the welcome screen is no longer stock behaviour on a fresh install
either - the OFF path was re-proven stock by S02's V17 (feed renders normally).

**Step 3 - the storm does not come back (20/20).** Twenty scripted cold starts
(force-stop, launch, wait 30 s, record focus, dump, count, BACK): search page in front
20/20, no sheet, no `IntroductionActivity`, zero `MorpheCred` lines per launch (the ask
never even fires on the guest path). One launch (12) recorded a transient launcher focus
- the previous launch's trailing BACK raced the relaunch; its UI read still said search,
and launches 13-20 are clean confirmation after it.

## Recovery for the future

`docs/REINSTALL-REDDIT.md` is the reinstall runbook (fast path, rebuild path, what can
break). Two device truths learned this session are recorded there and in HANDOVER.md:

- **Android backup restores Reddit's settings on reinstall.** The fresh install came up
  with the Morphe toggles already ON before anything was tapped - the device backup
  carried the old install's preference file across the uninstall. Never conclude a
  toggle state from "fresh install"; read the switch or verify behaviourally.
- The signing key matters to Google's per-app credential state: the same package with a
  different signing key did not storm. If the sheet pattern ever returns on a new
  install, that difference is the first thing to test.

## The final gate

`scripts/checkpoint.sh 4` (S04) is the final gate, and it is the ONLY place the V20
exception applies:

- it runs a fresh raw `scripts/checkpoint.sh all` and ties the run to the build (product
  commit + patched APK sha256, recorded in `evidence/S04-build-identity.txt`; read mode
  re-verifies both against the current tree and fails on any mismatch);
- it enforces `scripts/checks/S04-accepted-exceptions.txt` (V20: owner decision "option
  a, accepted as shipped", 2026-11-12, exact failure signature with mechanical markers):
  an unlisted red fails the gate; V20 failing a different way fails the gate; V20 now
  passing makes the exception stale and fails the gate until the entry is removed;
- the raw verdict stays an honest FAIL (1 of 4 checkpoints, because of V20) - asserted
  by the gate itself;
- **V11 is its own manual line**: "V11: manual, owner sign-off required", with the
  sign-off place in `scripts/checks/S04-v11-signoff.txt` (currently PENDING). V11 sits
  outside S03's 21 automated checks - S03 flags it in its log and counts it nowhere -
  and S04 never counts it as an automated pass.

Result this session: **S04 PASS, 8 of 8 checks** (evidence/S04.log), over a fresh raw run
whose per-checkpoint verdicts were exactly the recorded ones: S00 6/6 (six checks since
the 2026-11-11 V3 redefinition), S01 18/18, S02 13/13, S03 20/21 with V20 the only red -
the same failure signature as accepted (Trending / Trending Communities shelves and
trending rows still render in the search zero state; recent searches intact, evidence
`evidence/S03.log` and `evidence/S03-search-zero-state-after.png`).

## Steps

- [S4 - final gate](../scripts/checks/S04.sh) - the gate script itself; run via
  `scripts/checkpoint.sh 4`, fresh run by default, `S04_MODE=read` to re-verify a
  recorded run.

## For you to decide

- **V11 owner sign-off** (the notification-post test with a human finger): record it in
  `scripts/checks/S04-v11-signoff.txt` (signed-off-by + date) when done.
- The reviews still deferred (stage A and B reports); revive via `docs/REVIEW-PROMPT.md`
  whenever.
- The `.opencode/rules/hide-home-feed.md` pending edit (commit or discard) and
  `docs/PROJECT-HANDBOOK.md` (still untracked) - only the owner may call these.

## Review

Different model, new session:

    Read and follow docs/REVIEW-PROMPT.md for <range of this stage's commits>
