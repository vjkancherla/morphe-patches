#!/usr/bin/env bash
# S4 - Final gate: the recorded verdicts hold on a build-tied fresh raw run, with V20
# the only accepted red and V11 manual. Run via scripts/checkpoint.sh 4.
#
# The raw `scripts/checkpoint.sh all` verdict stays an honest FAIL (V20 is red-accepted,
# owner decision recorded in docs/build-plan.md). This gate is the ONLY place the
# accepted exception applies: a fresh run's per-row results are compared against
# scripts/checks/S04-accepted-exceptions.txt, and the run is tied to the build (product
# commit + patched APK sha256) in evidence/S04-build-identity.txt.
#
# Read mode: S04_MODE=read skips the fresh run and instead validates that the recorded
# run's identity (commit + sha256) matches the current tree exactly - a mismatch fails.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "Final gate: recorded verdicts hold on a build-tied raw run; V20 the only accepted red; V11 manual" <<'EOF'
Proves: every checkpoint's recorded verdict still holds on a FRESH raw
        scripts/checkpoint.sh all produced from the current product commit and the
        patched APK it built (or, in read mode, that the recorded run came from exactly
        this tree's commit and APK sha256). The accepted-exceptions file is enforced,
        not just recorded: an unlisted red fails the gate, a listed red failing in a
        different way fails the gate, and a listed row that now PASSES is a stale
        exception that fails the gate until removed.
How:    runs the raw all fresh (or validates the identity file in read mode), records
        the product commit + patched APK sha256, then applies the exceptions file to
        the per-checkpoint logs. V11 (notification post -> Back, needs a human finger)
        is its own manual line with the owner's sign-off place - never counted as an
        automated pass.
Needs:  JDK 21; for the fresh run: the phone attached over adb and UNLOCKED.
EOF

sha_of() {  # <file> -> sha256 or empty
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

# 1) The run itself: fresh raw all (or identity re-verification in read mode). ----------
if [ "${S04_MODE:-fresh}" = "read" ]; then
  identity_is_current() {
    [ -f evidence/S04-build-identity.txt ] || { echo "expected: evidence/S04-build-identity.txt from a recorded run"; echo "found:    the file does not exist - run S04 fresh first"; return 1; }
    rec_commit="$(sed -n 's/^commit: //p' evidence/S04-build-identity.txt)"
    rec_sha="$(sed -n 's/^patched-apk-sha256: //p' evidence/S04-build-identity.txt)"
    cur_commit="$(git rev-parse HEAD)"
    cur_sha="$(sha_of build/ckpt/patched.apk)"
    if [ "$rec_commit" != "$cur_commit" ]; then
      echo "expected: recorded commit $rec_commit"; echo "found:    current HEAD $cur_commit"; return 1
    fi
    if [ "$rec_sha" != "$cur_sha" ]; then
      echo "expected: recorded patched-apk sha256 $rec_sha"; echo "found:    current $cur_sha"; return 1
    fi
  }
  require "recorded run is tied to this tree: same product commit AND same patched APK sha256" \
    "look at: evidence/S04-build-identity.txt vs git rev-parse HEAD and the sha256 of build/ckpt/patched.apk" \
    identity_is_current
else
  run_raw_all() {
    set +e
    bash scripts/checkpoint.sh all > evidence/S04-raw.log 2>&1
    set -e
    return 0
  }
  require "fresh raw scripts/checkpoint.sh all runs to its verdict (its FAIL on V20 is expected and asserted below)" \
    "look at: evidence/S04-raw.log - the complete raw output of this gate's run" \
    run_raw_all

  identity_matches_tree() {
    commit="$(git rev-parse HEAD)"
    sha="$(sha_of build/ckpt/patched.apk)"
    printf 'mode: fresh-run\ndate: %s\ncommit: %s\npatched-apk-sha256: %s\n' \
      "$(date +%Y-%m-%dT%H:%M:%S%z)" "$commit" "$sha" > evidence/S04-build-identity.txt
    if [ "$(sed -n 's/^commit: //p' evidence/S04-build-identity.txt)" != "$commit" ] ||
       [ "$(sed -n 's/^patched-apk-sha256: //p' evidence/S04-build-identity.txt)" != "$sha" ]; then
      echo "expected: the identity file to record this run's commit and sha256"
      echo "found:    a mismatch - the run is not tied to this build"
      return 1
    fi
  }
  require "the run is tied to the build: product commit + patched APK sha256 recorded and matching" \
    "look at: evidence/S04-build-identity.txt (commit $(git rev-parse HEAD 2>/dev/null | cut -c1-9))" \
    identity_matches_tree
fi

# 2) The exceptions file: exactly the accepted entries, nothing else. --------------------
exceptions_hold_exactly_v20() {
  rows="$(grep -E '^row:' scripts/checks/S04-accepted-exceptions.txt | tr -d ' ' | sort -u | paste -sd, -)"
  if [ "$rows" != "row:V20" ]; then
    echo "expected: the exceptions file to list exactly row: V20"
    echo "found:    $rows"
    return 1
  fi
  decision="$(sed -n 's/^decision: //p' scripts/checks/S04-accepted-exceptions.txt)"
  date="$(sed -n 's/^date: //p' scripts/checks/S04-accepted-exceptions.txt)"
  if [ "$decision" != "option a, accepted as shipped" ] || [ "$date" != "2026-11-12" ]; then
    echo "expected: decision 'option a, accepted as shipped', dated 2026-11-12"
    echo "found:    decision='$decision' date='$date'"
    return 1
  fi
}
require "accepted-exceptions file: exactly V20, 'option a, accepted as shipped', 2026-11-12" \
  "look at: scripts/checks/S04-accepted-exceptions.txt" \
  exceptions_hold_exactly_v20

# 3) S00-S02: fully green on the fresh run. ----------------------------------------------
for n in 00 01 02; do
  check_eq "S${n} verdict green on the fresh run" \
    "look at: evidence/S${n}.log (regenerated by this gate's raw run)" \
    "PASS" "$(grep -oE "PASS: S${n}" evidence/S${n}.log | head -1 | cut -d: -f1)"
done

# 4) S03: exactly 21 automated checks, exactly one red, and it is V20. --------------------
s03_shape() {
  verdict="$(grep -E '^FAIL: S03 - [0-9]+ of [0-9]+ checks failed$' evidence/S03.log | head -1)"
  if [ "$verdict" != "FAIL: S03 - 1 of 21 checks failed" ]; then
    echo "expected: FAIL: S03 - 1 of 21 checks failed (the recorded shape)"
    echo "found:    ${verdict:-<no matching verdict line>}"
    return 1
  fi
  fails="$(grep -cE '^[[:space:]]*\[[0-9]+\] FAIL' evidence/S03.log)"
  if [ "$fails" -ne 1 ]; then
    echo "expected: exactly one failing automated check"; echo "found:    $fails"
    return 1
  fi
  if ! grep -E '^[[:space:]]*\[[0-9]+\] FAIL' evidence/S03.log | grep -q 'V20:'; then
    echo "expected: the single failing check to be V20"
    echo "found:    $(grep -E '^[[:space:]]*\[[0-9]+\] FAIL' evidence/S03.log)"
    return 1
  fi
}
require "S03 shape: 1 of 21 failed, and the failure is V20" \
  "look at: evidence/S03.log" \
  s03_shape

# 5) The V20 exception: same signature, not stale. ----------------------------------------
v20_signature_unchanged() {
  block="$(sed -n '/^[[:space:]]*\[[0-9]*\] FAIL/,/look at:/p' evidence/S03.log)"
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*\[[0-9]+\] ok'; then
    echo "expected: the listed row V20 to still FAIL"; echo "found:    an ok verdict inside its block - the exception is STALE; remove it from scripts/checks/S04-accepted-exceptions.txt"; return 1
  fi
  if ! printf '%s' "$block" | grep -q 'text="Trending Communities"' ||
     ! printf '%s' "$block" | grep -q 'text="Trending"'; then
    echo "expected: the accepted signature's Trending / Trending Communities shelves in the failure dump"
    echo "found:    neither marker - V20 now fails a DIFFERENT way; the exception does not cover it"
    printf '%s\n' "$block" | head -12 | sed 's/^/        | /'
    return 1
  fi
  if ! printf '%s' "$block" | grep -Eq 'text="(Recent|History)"'; then
    echo "expected: recent searches intact inside the failure dump (the accepted signature)"
    echo "found:    no Recent/History marker - V20 fails a DIFFERENT way; the exception does not cover it"
    printf '%s\n' "$block" | head -12 | sed 's/^/        | /'
    return 1
  fi
}
require "V20 fails exactly the accepted signature (Trending shelves render; recent searches intact)" \
  "look at: evidence/S03.log's V20 block vs scripts/checks/S04-accepted-exceptions.txt" \
  v20_signature_unchanged

# 6) The raw verdict stays an honest FAIL. ------------------------------------------------
raw_stays_failed() {
  if grep -q '^FAIL: 1 of 4 checkpoints failed' evidence/S04-raw.log; then
    return 0
  fi
  echo "expected: the raw all verdict to stay FAIL (1 of 4, because of the red-accepted V20)"
  echo "found:    $(grep -E '^(PASS|FAIL): [0-9] of 4 checkpoints' evidence/S04-raw.log | tail -1)"
  echo "          if the raw run PASSED, V20 is fixed and the exception is stale -"
  echo "          remove it from scripts/checks/S04-accepted-exceptions.txt, then re-run S04"
  return 1
}
require "the raw scripts/checkpoint.sh all verdict stays FAIL (the exception applies to this gate only)" \
  "look at: the verdict lines at the end of evidence/S04-raw.log" \
  raw_stays_failed

# 7) V11: its own manual line, never an automated pass. -----------------------------------
so_by="$(sed -n 's/^signed-off-by: //p' scripts/checks/S04-v11-signoff.txt)"
so_date="$(sed -n 's/^date: //p' scripts/checks/S04-v11-signoff.txt)"
if [ -n "$so_by" ] && [ "$so_by" != "PENDING" ]; then
  note "V11: manual, signed off by ${so_by:-?} on ${so_date:-?} (scripts/checks/S04-v11-signoff.txt) - owner sign-off required; NOT counted as an automated pass"
else
  note "V11: manual, owner sign-off required - PENDING (record it in scripts/checks/S04-v11-signoff.txt: signed-off-by + date); NOT counted as an automated pass"
fi
note "V11 sits outside S03's 21 automated checks: S03 flags it in its log ('needs a human finger, flagged, not skipped') and counts it nowhere."

finish
