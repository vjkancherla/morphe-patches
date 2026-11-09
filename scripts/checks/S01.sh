#!/usr/bin/env bash
# S1 - No feed renders, and cold start lands on search.
# Written from docs/build-plan.md step S1 Check lines (v2, amended 2026-11-09). Run via
# scripts/checkpoint.sh 1.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "S1: no feed renders, and cold start lands on search" <<'EOF'
Proves: the five feed screens are guarded at their render method, hook 1 replaces the
        cold-start Home with the Communities start tab (decision Option A; the Home button
        stays in the bar), and - with *Hide feeds* ON as a guest with no account - a cold
        start opens Reddit's search page; Back returns to the Communities tab with its top
        bar over an empty page, its search button opens search again, and nothing crashes.
How:    rebuilds and re-patches (V2 again; the result file only reports success if every
        filter matched and each hook call sits at instruction index 0, which the patch
        re-checks after injecting). On the phone: installs this build if it is not already
        there (this wipes the app's data - the accepted disposable test device), gates on
        the phone being unlocked (adb cannot clear a secure keyguard), cold-starts the app,
        confirms before anything else that Reddit itself is in the foreground, and asserts
        the search page. Then presses Back, asserts the search page is gone with the
        Communities top bar over an empty page, taps that bar's search button and asserts
        search again. Never taps Home in S1 (Reddit still selects Home until hooks 2-3
        land). logcat must show no patch failure and no crash.
Needs:  ./gradlew buildAndroid producing the bundle; the 2026.45.0 .apkm; a phone attached
        over adb and UNLOCKED; *Hide feeds* switched ON as a guest
        (Morphe -> Navigation bar -> Hide feeds). No login is used or expected. The
        Communities bar slot is server-controlled and may be absent: no check requires it.
EOF

build_android() { ./gradlew buildAndroid; }
require "gradle buildAndroid succeeds" "look at: gradle output above" build_android

patch_apk() {
  java -jar ../tools/morphe-desktop-2.1.1-all.jar patch \
    -p "$BUNDLE" -o "$OUT_DIR/patched.apk" -r "$OUT_DIR/result.json" "$APKM"
}
require "morphe-desktop patches the .apkm clean (V2, re-run)" \
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
check "result file: success, no failed patch, hide-nav applied (all five guards matched, hooks at index 0)" \
  "look at: $OUT_DIR/result.json (appliedPatches/failedPatches)" result_clean

device_attached() {
  $ADB devices | tail -n +2 | grep -c "device$"
}
require "a phone is attached over adb (waiting for the phone if empty)" \
  "look at: adb devices output above; plug in the test phone with USB debugging on" device_attached

# The phone has a secure keyguard that adb cannot clear. Do not wake, swipe or tap until the
# owner has unlocked it. A locked phone is a stop, not something to work around.
phone_unlocked() {
  policy="$($ADB shell dumpsys window policy 2>/dev/null)"
  if printf '%s' "$policy" | grep -q "mIsShowing=true"; then
    echo "expected: the phone unlocked, with no keyguard showing"
    echo "found:    the keyguard is showing ($(printf '%s' "$policy" | grep -m1 'secure=' | sed 's/^ *//'))"
    echo "look at:  unlock the phone yourself, keep it unlocked, then re-run scripts/checkpoint.sh 1"
    return 1
  fi
  return 0
}
require "the phone is unlocked by the owner (adb cannot clear its lock screen)" \
  "look at: the keyguard message above" phone_unlocked

# --- install: fresh only if the installed app is not this patched build ----------

# Marker: this step's hook 1 entry point, added 2026-11-09 (the start-tab replacement).
# A build without it (including the pre-hook-1 S1 guards build) gets refreshed, with the
# one accepted data wipe.
MARKER="getStartTab"

installed_patched() {
  base="$($ADB shell pm path "$PACKAGE" 2>/dev/null | head -1 | sed 's/package://' | tr -d '\r')"
  [ -n "$base" ] || return 1
  $ADB shell "unzip -o -q $base '*.dex' -d /data/local/tmp/ckpt_dex >/dev/null 2>&1; grep -l '$MARKER' /data/local/tmp/ckpt_dex/*.dex >/dev/null 2>&1"
}

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
")"
    if [ -n "$result" ]; then
      $ADB shell input tap $result
    fi
    sleep 2
  done >/dev/null 2>&1
}

install_fresh() {
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB uninstall "$PACKAGE" >/dev/null 2>&1
  ($ADB install -r "$OUT_DIR/patched.apk" 2>&1 | grep -q "Success") &
  install_pid=$!
  sleep 3
  confirm_install_sheet "$install_pid" &
  confirm_pid=$!
  wait "$install_pid"
  install_rc=$?
  kill "$confirm_pid" 2>/dev/null || true
  return $install_rc
}

if installed_patched; then
  note "Installed app already carries this build - keeping its toggle state."
else
  require "patched build installed fresh on the phone (wipes its Reddit data - accepted)" \
    "look at: adb install output above" install_fresh
  note "A fresh install wipes app data, so *Hide feeds* is OFF. Turn it ON as a guest now:"
  note "-> Morphe -> Navigation bar -> Hide feeds. No login is needed or wanted."
  note "-> Then re-run scripts/checkpoint.sh 1; this install is kept, toggle and all."
  toggle_gate() {
    echo "expected: *Hide feeds* switched ON as a guest after the fresh install"
    echo "found:    a fresh install, whose setting defaults to OFF"
    echo "look at:  turn it on as a guest (Morphe -> Navigation bar -> Hide feeds), then re-run"
    return 1
  }
  check "Hide feeds is ON as a guest (one-time phone step after a fresh install)" \
    "look at: the note above" toggle_gate
  finish
fi

# --- device behavior ------------------------------------------------------------

ui_text() {
  $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
  $ADB shell cat /sdcard/window_dump.xml 2>/dev/null
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
pat = re.compile(r'(?:text|content-desc)=\"' + re.escape(label) + r'\"[^>]*bounds=\"\\[(\d+),(\d+)\\]\\[(\d+),(\d+)\\]\"')
m = pat.search(xml)
print((int(m.group(1))+int(m.group(3)))//2, (int(m.group(2))+int(m.group(4)))//2) if m else ''
"
}

dump_texts() {  # <dump>
  printf '%s' "$1" | grep -Eo '(text|content-desc)="[^"]{1,30}"' 2>/dev/null | sort -u | head -12 || true
}

bar_summary() {  # <dump>
  printf '%s' "$1" | grep -Eo '(text|content-desc)="(Home|Create|Inbox|You|Communities|Answers|Games)"' 2>/dev/null | tr '\n' ' ' || true
}

# 1) Cold start landing -----------------------------------------------------------

cold_start_lands_on_search() {
  cold_start
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  dump="$(ui_text)"
  if ! printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: Reddit's search page ('Search Reddit' hint) on cold start (hook 1 -> Communities attach -> search)"
    echo "found:    no search page in the cold-start dump"
    echo "bar:      $(bar_summary "$dump")"
    echo "seen:     $(dump_texts "$dump")"
    echo "look at:  is *Hide feeds* ON? (Morphe -> Navigation bar -> Hide feeds, as a guest)"
    echo "look at:  adb logcat -d | grep 'getStartTab failure\\|onStartTabAttached failure'"
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
check "cold start: Reddit's search page opens as a guest, no login, no feed" \
  "look at: uiautomator dump, the Hide feeds toggle, logcat" cold_start_lands_on_search

home_button_in_bar() {
  dump="$(ui_text)"
  if ! printf '%s' "$dump" | grep -Eq '(text|content-desc)="Home"'; then
    echo "expected: the Home button stay in the bottom bar (owner amendment; no feed ever)"
    echo "found:    no Home node in the bar -"
    echo "bar:      $(bar_summary "$dump")"
    return 1
  fi
  echo "bottom bar as seen by the check: $(bar_summary "$dump")"
  echo "(the Communities slot is server-controlled and may be absent on this phone;"
  echo " every check here passes with or without it.)"
  return 0
}
check "Home button stays in the bar (its screen stays feed-free via the guard)" \
  "look at: the bar summary line above" home_button_in_bar

# 2) Back to the empty start screen ----------------------------------------------

back_to_empty_start_screen() {
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 3
  dump="$(ui_text)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: Back leaves the search page"
    echo "found:    the search page is still showing"
    return 1
  fi
  if feed_markers_present "$dump"; then
    echo "expected: the empty start screen under the Communities top bar (no Discover feed)"
    echo "found:    feed action markers in the dump after Back - a feed is visible"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if ! printf '%s' "$dump" | grep -Eq '(text|content-desc)="Search"'; then
    echo "expected: the Communities top bar over the empty page, with its search button"
    echo "found:    no Search node in the dump - the top bar may not have attached"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if ! $ADB shell pidof "$PACKAGE" >/dev/null 2>&1; then
    echo "expected: the app still running after Back"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  echo "the empty start screen is up under the Communities top bar, with no feed markers;"
  echo "dump left for the owner to eyeball: $(dump_texts "$dump")"
  return 0
}
check "Back from search: empty page under the Communities top bar, no feed, no crash" \
  "look at: uiautomator dump and logcat" back_to_empty_start_screen

# 3) The top bar's search button -------------------------------------------------

search_button_reopens_search() {
  dump="$(ui_text)"
  coords="$(node_center "$dump" "Search")"
  if [ -z "$coords" ]; then
    echo "expected: the Communities top bar's search button"
    echo "found:    no Search node to tap"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  $ADB shell input tap $coords
  sleep 4
  after="$(ui_text)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! printf '%s' "$after" | grep -q "Search Reddit"; then
    echo "expected: the search page again after tapping the top bar's search button"
    echo "found:    no search page 4s after the tap"
    echo "seen:     $(dump_texts "$after")"
    return 1
  fi
  if feed_markers_present "$after"; then
    echo "expected: the search page before typing shows no feed cards"
    echo "found:    feed action markers in the search-page dump - this needs the owner's eyes"
    return 1
  fi
  return 0
}
check "the empty start screen's search button opens search again" \
  "look at: uiautomator dump" search_button_reopens_search

# 4) Logs ------------------------------------------------------------------------

log_clean() {
  out="$($ADB logcat -d 2>/dev/null)"
  ! printf '%s' "$out" | grep -q "getStartTab failure" &&
    ! printf '%s' "$out" | grep -q "onStartTabAttached failure" &&
    ! printf '%s' "$out" | grep -q "FATAL EXCEPTION"
}
check "no patch failure and no crash over the whole run" \
  "look at: adb logcat -d for 'getStartTab failure', 'onStartTabAttached failure' or 'FATAL EXCEPTION'" log_clean

finish
