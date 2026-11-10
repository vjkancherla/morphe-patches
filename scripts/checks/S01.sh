#!/usr/bin/env bash
# S1 - No feed renders, cold start lands on search by itself, Home taps open search.
# Written from docs/build-plan.md step S1 Check lines and the third amendment
# (hooks 5-6, 2026-11-09/10). Run via scripts/checkpoint.sh 1.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "S1: no feed renders; cold start opens search; every Home tap opens search" <<'EOF'
Proves: with *Hide feeds* ON as a guest (no account): hook 5 opens the search page by
        itself on cold start (never a login prompt, never a feed); the guard keeps every
        feed screen off; Back closes the keyboard then the search page and lands under the
        Communities top bar, whose menu reaches the Morphe entry; hook 6 opens search on
        EVERY bottom-bar Home tap - three or more taps in a row, closing search between
        them, each open search and the bare blank Home page never appears; a searched
        subreddit opens and Back returns to search. Nothing crashes.
How:    rebuilds and re-patches (the result file only reports success if every filter
        matched and each hook call sits exactly where it claims, re-checked after
        injecting). ALWAYS installs the freshly patched build with `install -r` (data,
        toggle and guest state kept - no marker-based skip, so a check can never run
        against an older build). Cold-starts the app, confirms Reddit itself is in the
        foreground before any assertion (a dump of anything else is a harness error,
        never a result), and works the phone through the flows above with uiautomator
        dumps; logcat must stay free of patch failures and crashes.
Needs:  ./gradlew buildAndroid producing the bundle; the 2026.45.0 .apkm; a phone
        attached over adb and UNLOCKED; *Hide feeds* already ON as a guest
        (Morphe -> Navigation bar -> Hide feeds; a one-time owner step, the toggle
        survives `install -r`). No login is used or expected. The Communities bar slot
        is server-controlled: the checks are written to pass with or without it.
EOF

build_android() { ./gradlew buildAndroid; }
require "gradle buildAndroid succeeds" "look at: gradle output above" build_android

patch_apk() {
  java -jar ../tools/morphe-desktop-2.1.1-all.jar patch \
    -p "$BUNDLE" -o "$OUT_DIR/patched.apk" -r "$OUT_DIR/result.json" "$APKM"
}
require "morphe-desktop patches the .apkm clean (re-run every checkpoint)" \
  "look at: jar output above and $OUT_DIR/result.json" patch_apk

result_clean() {
  python3 -c "
import json
r = json.load(open('$OUT_DIR/result.json'))
assert r['success'], 'result.success is false'
assert not r['failedPatches'], 'failedPatches: %r' % (r['failedPatches'],)
assert 'Hide navigation buttons' in r['appliedPatches'], 'Hide navigation buttons not applied'
"
}
check "result file: success, no failed patch, hide-nav applied" \
  "look at: $OUT_DIR/result.json (appliedPatches/failedPatches)" result_clean

device_attached() {
  $ADB devices | tail -n +2 | grep -c "device$"
}
require "a phone is attached over adb" \
  "look at: adb devices output above; plug in the test phone with USB debugging on" device_attached

# The phone has a secure keyguard that adb cannot clear. Do not wake, swipe or tap until the
# owner has unlocked it. A locked phone is a stop, not something to work around.
phone_unlocked() {
  policy="$($ADB shell dumpsys window policy 2>/dev/null)"
  if printf '%s' "$policy" | grep -q "mIsShowing=true"; then
    echo "expected: the phone unlocked, with no keyguard showing"
    echo "found:    the keyguard is showing"
    echo "look at:  unlock the phone yourself, keep it unlocked, then re-run scripts/checkpoint.sh 1"
    return 1
  fi
  return 0
}
require "the phone is unlocked by the owner (adb cannot clear its lock screen)" \
  "look at: the keyguard message above" phone_unlocked

# --- install: the freshly patched build, every run -------------------------------

confirm_install_sheet() {
  # ColorOS gates every adb install behind an on-device confirmation sheet; poll and tap it.
  # If it never appears (some builds with install-permission pre-granted), the poll simply
  # times out and the install proceeds on its own.
  for attempt in $(seq 1 18); do
    $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
    result="$($ADB shell cat /sdcard/window_dump.xml 2>/dev/null | python3 -c "
import re, sys
xml = sys.stdin.read()
pat = re.compile(r'text=\"Continue installation\"[^>]*bounds=.{0,20}?\\[(\d+),(\d+)\\]\\[(\d+),(\d+)\\]')
m = pat.search(xml)
print((int(m.group(1))+int(m.group(3)))//2, (int(m.group(2))+int(m.group(4)))//2) if m else ''
")" || true
    if [ -n "$result" ]; then
      $ADB shell input tap $result
    fi
    sleep 2
  done >/dev/null 2>&1
}

install_freshly_patched_build() {
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB shell am force-stop "$PACKAGE" >/dev/null 2>&1
  ($ADB install -r "$OUT_DIR/patched.apk" 2>&1 | grep -q "Success") &
  install_pid=$!
  sleep 3
  confirm_install_sheet &
  confirm_pid=$!
  wait "$install_pid"
  install_rc=$?
  kill "$confirm_pid" 2>/dev/null || true
  return $install_rc
}
require "the freshly patched build installed with install -r (data and toggle kept)" \
  "look at: adb install output above; the toggle must already be ON (see describe)" install_freshly_patched_build

# --- device behavior ---------------------------------------------------------------

ui_text() {
  $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
  $ADB shell cat /sdcard/window_dump.xml 2>/dev/null
}

# uiautomator dumps can come back empty when the tree is mid-layout; retry rather than
# reading a raced dump as a result.
ui_text_retried() {
  for attempt in 1 2 3; do
    dump="$(ui_text)"
    [ -n "$dump" ] && grep -q 'bounds="' <<<"$dump" && { printf '%s' "$dump"; return 0; }
    sleep 2
  done
  printf '%s' "$dump"
}

# Poll every few seconds until a grep pattern appears in the dump (or the budget runs out).
# The bar and its menu attach on a lag a single sleep misses.
wait_for_ui() {  # <egrep pattern> <seconds budget>
  deadline=$(( $(date +%s) + $2 ))
  while :; do
    dump="$(ui_text_retried)"
    if printf '%s' "$dump" | grep -Eq "$1"; then
      printf '%s' "$dump"
      return 0
    fi
    sleep 2
    [ "$(date +%s)" -lt "$deadline" ] || { printf '%s' "$dump"; return 1; }
  done
}

# A uiautomator dump of anything that is not Reddit is a harness error: it must never read
# as a result about the app. Run before every assertion.
reddit_in_front() {
  focus="$($ADB shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')"
  case "$focus" in
    *"$PACKAGE"*) return 0 ;;
    *)
      echo "expected: Reddit in the foreground before any assertion"
      echo "found:    the front window is: $focus"
      echo "look at:  the launch step below failed - fix the start commands, never the app"
      return 1
      ;;
  esac
  return 0
}

# Cold start through the resolved launcher activity, like a fresh launch by hand.
cold_start() {
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB shell am force-stop "$PACKAGE" >/dev/null 2>&1
  sleep 1
  # `monkey` intermittently left the launcher in front; start the resolved launcher
  # activity and poll for the window instead.
  activity="$($ADB shell cmd package resolve-activity --brief "$PACKAGE" 2>/dev/null | tail -1 | tr -d '\r')"
  [ -n "$activity" ] || activity="$PACKAGE/launcher.default"
  $ADB shell am start -n "$activity" >/dev/null 2>&1
  for attempt in $(seq 1 20); do
    $ADB shell dumpsys window 2>/dev/null | grep -q "mCurrentFocus=.*$PACKAGE" && break
    sleep 1
  done
  sleep 3
}

# Feed cards expose vote/comment/share actions. A blank feed page has none of these.
# Subreddit pages the guest opens on purpose are exempt (their feed is Reddit's own).
feed_markers_present() {
  printf '%s' "$1" | grep -Eq 'content-desc="(Upvote|Downvote|Comment|Share)"|text="(Upvote|Downvote|Share)"'
}

# A login prompt shows these calls to action. The feature must work with no account.
login_markers_present() {
  printf '%s' "$1" | grep -Eqi '(text|content-desc)="(log ?in|sign ?up|sign ?in|join reddit|continue with)"'
}

node_center() {  # <dump> <label>
  printf '%s' "$1" | LABEL="$2" python3 -c "
import os, re, sys
xml = sys.stdin.read()
label = os.environ['LABEL']
# Every uiautomator node has a text attr (often empty) before its content-desc, so scan
# BOTH attr values per node; matching the first attr alone would hide content-desc-only
# labels (the top bar's menu, the search hint).
for node in xml.split('<node ')[1:]:
  t = re.search(r'\btext=\"([^\"]*)\"', node)
  c = re.search(r'\bcontent-desc=\"([^\"]*)\"', node)
  for val in (t.group(1) if t else '', c.group(1) if c else ''):
    if val and (val == label or val.startswith(label)):
      b = re.search(r'bounds=\"\\[(\d+),(\d+)\\]\\[(\d+),(\d+)\\]\"', node)
      if b:
        print((int(b.group(1))+int(b.group(3)))//2, (int(b.group(2))+int(b.group(4)))//2)
        break
"
}

dump_texts() {  # <dump>
  printf '%s' "$1" | grep -Eo '(text|content-desc)="[^"]{1,30}"' 2>/dev/null | sort -u | head -12 || true
}

bar_summary() {  # <dump>
  printf '%s' "$1" | grep -Eo '(text|content-desc)="(Home|Create|Inbox|You|Communities|Answers|Games)"' 2>/dev/null | tr '\n' ' ' || true
}

tap_node() {  # <dump> <label>  -> taps the node's center; empty output means nothing to tap
  coords="$(node_center "$1" "$2")"
  [ -n "$coords" ] && $ADB shell input tap $coords
}

# Press Back once per round until the search page is gone (the first Back typically only
# closes the keyboard). Asserts nothing itself; the caller does.
close_search_with_back() {
  for round in 1 2 3; do
    dump="$(ui_text)"
    printf '%s' "$dump" | grep -q "Search Reddit" || return 0
    $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
    sleep 3
  done
  return 1   # still open after three rounds; the caller reports
}

bar_top_present() {  # <dump>  the Communities top bar over the empty start screen
  printf '%s' "$1" | grep -Eq 'Open community menu|text="search on Reddit"|(text|content-desc)="Search"'
}

process_alive() {
  $ADB shell pidof "$PACKAGE" >/dev/null 2>&1
}

# 1) Cold start landing (hook 5; V5) ------------------------------------------------

cold_start_opens_search() {
  cold_start
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  dump="$(ui_text)"
  if ! printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: the search page ('Search Reddit') opens by itself on cold start (hook 5)"
    echo "found:    no search page in the cold-start dump"
    echo "bar:      $(bar_summary "$dump")"
    echo "seen:     $(dump_texts "$dump")"
    echo "look at:  is *Hide feeds* ON? (Morphe -> Navigation bar -> Hide feeds, as a guest)"
    echo "look at:  adb logcat -d | grep 'getStartTab failure\\|onStartTabAttached failure\\|openSearchPage failure'"
    return 1
  fi
  if login_markers_present "$dump"; then
    echo "expected: search opens with no login prompt (the app must work as a guest)"
    echo "found:    a login call-to-action in the search-page dump - stopping for the owner:"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if feed_markers_present "$dump"; then
    echo "expected: the search page before typing shows no feed cards"
    echo "found:    feed action markers in the search-page dump - this needs the owner's eyes"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  return 0
}
check "cold start: Reddit's search page opens by itself as a guest, no login, no feed" \
  "look at: uiautomator dump, the Hide feeds toggle, logcat" cold_start_opens_search

# 2) Back out of the cold-start search: keyboard closes, then the search page is gone ------
#    (No Communities top bar is required here: the cold-start search comes from the guarded
#    HomePagerScreen's attach (hook 5), and backing out lands on that blank screen ==
#    measured 2026-11-10, bar labels only. The top bar is asserted on the Home-tap flows.)

back_out_of_cold_start_search() {
  if ! close_search_with_back; then
    echo "expected: Back closes the keyboard, then the search page"
    echo "found:    the search page is still up after three rounds of Back"
    return 1
  fi
  dump="$(ui_text_retried)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: the search page gone after Back"
    echo "found:    the search page is still showing"
    return 1
  fi
  if feed_markers_present "$dump"; then
    echo "expected: no feed after backing out of the cold-start search"
    echo "found:    feed action markers in the dump - a feed is visible"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if ! process_alive; then
    echo "expected: the app still running after Back"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  echo "backed out of the cold-start search: no feed, no crash"
  echo "seen:     $(dump_texts "$dump")"
  return 0
}
check "Back from the cold-start search: keyboard then page gone, no feed, no crash" \
  "look at: uiautomator dump and logcat" back_out_of_cold_start_search

home_button_in_bar() {
  # The search page covers the bar right after a cold start; close it first (idempotent -
  # it is already closed when this check runs right after the back-out check).
  close_search_with_back
  dump="$(wait_for_ui '(text|content-desc)="Home"' 12)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! printf '%s' "$dump" | grep -Eq '(text|content-desc)="Home"'; then
    echo "expected: the Home button stays in the bar (owner amendment; every tap opens search)"
    echo "found:    no Home node in the bar -"
    echo "bar:      $(bar_summary "$dump")"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  echo "bottom bar as seen by the check: $(bar_summary "$dump")"
  return 0
}
check "Home button stays in the bar" "look at: the bar summary line above" home_button_in_bar

# 3) Every Home tap opens search (hook 6; V18) - three or more, closing between -------

home_tap_flow() {  # called with search closed; asserts search opens after a Home tap
  if ! back_eof_ok="$(reddit_in_front)"; then { echo "$back_eof_ok"; return 1; }; fi
  dump="$(ui_text)"
  coords="$(node_center "$dump" "Home")"
  if [ -z "$coords" ]; then
    echo "expected: a Home node in the bar to tap"
    echo "found:    none -"
    echo "bar:      $(bar_summary "$dump")"
    return 1
  fi
  echo "tapping Home at $coords"
  $ADB shell input tap $coords
  sleep 4
  after="$(ui_text)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! printf '%s' "$after" | grep -q "Search Reddit"; then
    echo "expected: the search page opens after the Home tap (hook 6)"
    echo "found:    no search page 4s after the tap - the bare blank Home page?! (V18 fail)"
    echo "bar:      $(bar_summary "$after")"
    echo "seen:     $(dump_texts "$after")"
    return 1
  fi
  if feed_markers_present "$after"; then
    echo "expected: the search page shows no feed cards"
    echo "found:    feed action markers in the search-page dump - this needs the owner's eyes"
    return 1
  fi
  return 0
}

# Back out of a Home-tap round: search gone, Communities top bar over an empty page
# (after a tap flow the underlying screen IS the Communities screen - hook 6 runs the
# selection funnel, so its attach is the real one; measured 2026-11-10).
back_to_top_bar() {
  if ! close_search_with_back; then
    echo "expected: Back closes the keyboard, then the search page"
    echo "found:    the search page is still up after three rounds of Back"
    return 1
  fi
  # The top bar attaches underneath with a lag a single dump misses.
  dump="$(wait_for_ui 'Open community menu|text="search on Reddit"|(text|content-desc)="Search"' 12)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: the search page gone after Back"
    echo "found:    the search page is still showing"
    return 1
  fi
  if feed_markers_present "$dump"; then
    echo "expected: the empty start screen under the Communities top bar (no feed)"
    echo "found:    feed action markers in the dump after Back - a feed is visible"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if ! bar_top_present "$dump"; then
    echo "expected: the Communities top bar over the empty page"
    echo "found:    no top-bar node in the dump - the bar may not have attached"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if ! process_alive; then
    echo "expected: the app still running after Back"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  echo "empty page under the Communities top bar; dump left for the owner:"
  echo "seen:     $(dump_texts "$dump")"
  return 0
}

for tap_round in 1 2 3; do
  require "Home tap ${tap_round}/3 opens search" "look at: uiautomator dump after the tap" home_tap_flow
  require "back out of search ${tap_round}/3: top bar over empty page, no feed" \
    "look at: uiautomator dump after Back" back_to_top_bar
done

# 4) The Communities menu reaches the Morphe entry (settings stay reachable) ---------

menu_reaches_morphe() {
  # Coming from the round loop we are under the top bar; be sure.
  close_search_with_back
  dump="$(ui_text_retried)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  tap_node "$dump" "Open community menu"
  # The menu slides in with a lag; poll for the Morphe entry instead of a fixed sleep.
  menu="$(wait_for_ui '(text|content-desc)="[^"]*[Mm]orphe[^"]*"' 15)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! printf '%s' "$menu" | grep -Eiq '(text|content-desc)="[^"]*morphe[^"]*"'; then
    echo "expected: the Communities top bar's menu holds the Morphe entry"
    echo "found:    no Morphe node after opening the menu"
    echo "seen:     $(dump_texts "$menu")"
    $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
    return 1
  fi
  echo "menu open; the Morphe entry is reachable ($(dump_texts "$menu" | grep -i morphe))"
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  return 0
}
check "the Communities menu reaches the Morphe entry (Morphe settings stay reachable)" \
  "look at: uiautomator dump of the open menu" menu_reaches_morphe

# 5) Guest search: r/soccer opens, Back returns to search (V6) ------------------------

search_opens_subreddit() {
  dump="$(ui_text)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  # Through the top bar's search button when present, else through a Home tap.
  if bar_top_present "$dump"; then
    tap_node "$dump" "Search"
    sleep 3
    state="$(ui_text)"
    if ! printf '%s' "$state" | grep -q "Search Reddit"; then
      home_tap_flow || return 1
    fi
  else
    home_tap_flow || return 1
  fi
  sleep 2
  state="$(ui_text)"
  if ! printf '%s' "$state" | grep -q "Search Reddit"; then
    echo "expected: the search page"
    echo "found:    no search page before typing the subreddit"
    echo "seen:     $(dump_texts "$state")"
    return 1
  fi
  $ADB shell input text 'soccer' >/dev/null 2>&1
  sleep 4
  results="$(ui_text)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  echo "search results seen: $(dump_texts "$results")"
  tap_node "$results" "r/soccer"
  sleep 5
  community="$(ui_text)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! printf '%s' "$community" | grep -Eqi 'soccer'; then
    echo "expected: the r/soccer community page (sort tabs, joined state, feed)"
    echo "found:    nothing soccer-shaped after tapping the r/soccer suggestion"
    echo "seen:     $(dump_texts "$community")"
    return 1
  fi
  if ! process_alive; then
    echo "expected: the app alive after opening r/soccer"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  # Back returns to search (Reddit's own stack). On the results page the typed query has
  # replaced the hint, so the search page is recognized by hint OR query text.
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 4
  back="$(wait_for_ui 'Search Reddit|text="soccer"' 12)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! printf '%s' "$back" | grep -Eq 'Search Reddit|text="soccer"'; then
    echo "expected: Back from r/soccer returns to search (the 'Search Reddit' hint or typed query)"
    echo "found:    no search page after Back from the community"
    echo "seen:     $(dump_texts "$back")"
    return 1
  fi
  echo "search page is up again after Back from r/soccer ($(dump_texts "$back" | head -4 | tr '\n' ' '))"
  return 0
}
check "guest search 'soccer' opens r/soccer; Back returns to search" \
  "look at: uiautomator prints in the log above; a dump of the launcher is a harness error" search_opens_subreddit

# 6) Logs --------------------------------------------------------------------------

log_clean() {
  out="$($ADB logcat -d 2>/dev/null)"
  ! printf '%s' "$out" | grep -qE '"?(getStartTab|onBottomTabTapped|onStartTabAttached|openSearchPage|filterSearchZeroState) failure' &&
    ! printf '%s' "$out" | grep -q "FATAL EXCEPTION"
}
check "no patch failure and no crash over the whole run" \
  "look at: adb logcat -d for the hook failures or 'FATAL EXCEPTION'" log_clean

finish
