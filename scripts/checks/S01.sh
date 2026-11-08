#!/usr/bin/env bash
# S1 - No feed renders, and Communities opens search.
# Written from docs/build-plan.md step S1 Check lines (v2). Run via scripts/checkpoint.sh 1.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "S1: no feed renders, and Communities opens search" <<'EOF'
Proves: the five feed screens are guarded at their render method and the drawer route is
        gone. With *Hide feeds* ON, as a guest with no account, tapping Communities opens
        Reddit's search page; Back returns to the Communities tab with its top bar over an
        empty page - no Discover feed - and nothing crashes.
How:    rebuilds and re-patches (V2 again; a fingerprint miss on a guard fails the patch, so
        a clean result proves all five matched). On the phone: installs this build if it is
        not already there (this wipes the app's data - the accepted disposable test device),
        gates on the phone being unlocked (adb cannot clear a secure keyguard), cold-starts
        the app, taps Communities via uiautomator, and asserts the search page. Then presses
        Back and asserts the search page is gone, no feed markers are present, and the app
        is still alive. logcat must show no patch failure and no crash.
Needs:  ./gradlew buildAndroid producing the bundle; the 2026.45.0 .apkm; a phone attached
        over adb and UNLOCKED; *Hide feeds* switched ON as a guest
        (Morphe -> Navigation bar -> Hide feeds). No login is used or expected.
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
check "result file: success, no failed patch, hide-nav applied (all five guards matched)" \
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

# Marker: this step's guard entry point. A build without it (including the old drawer
# spike) lacks the guards and gets refreshed, with the one accepted data wipe.
MARKER="hideFeedScreen"

installed_patched() {
  base="$($ADB shell pm path "$PACKAGE" 2>/dev/null | head -1 | sed 's/package://' | tr -d '\r')"
  [ -n "$base" ] || return 1
  $ADB shell "unzip -o -q $base '*.dex' -d /data/local/tmp/ckpt_dex >/dev/null 2>&1; grep -l '$MARKER' /data/local/tmp/ckpt_dex/*.dex >/dev/null 2>&1"
}

confirm_install_sheet() {
  # ColorOS gates every adb install behind an on-device confirmation sheet; poll and tap it.
  # If it never appears (some builds with install-permission pre-granted), the poll simply
  # times out and the install proceeds on its own.
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
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

bring_to_front() {
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB shell am force-stop "$PACKAGE" >/dev/null 2>&1
  # `monkey` intermittently left the launcher in front; start the resolved launcher
  # activity and poll for the window instead.
  activity="$($ADB shell cmd package resolve-activity --brief "$PACKAGE" 2>/dev/null | tail -1 | tr -d '\r')"
  [ -n "$activity" ] || activity="$PACKAGE/launcher.default"
  $ADB shell am start -n "$activity" >/dev/null 2>&1
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    $ADB shell dumpsys window 2>/dev/null | grep -q "mCurrentFocus=.*$PACKAGE" && break
    sleep 1
  done
  sleep 2
}

ui_text() {
  $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
  $ADB shell cat /sdcard/window_dump.xml 2>/dev/null
}

# Feed cards expose vote/comment/share actions. A blank feed page has none of these.
feed_markers_present() {
  printf '%s' "$1" | grep -Eq 'content-desc="(Upvote|Downvote|Comment|Share)"|text="(Upvote|Downvote|Share)"'
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

tap_communities_expect_search() {
  bring_to_front
  dump="$(ui_text)"
  coords="$(node_center "$dump" "Communities")"
  if [ -z "$coords" ]; then
    echo "expected: a bottom-bar tab labelled Communities"
    echo "found:    no Communities node in the cold-start dump"
    echo "seen:     $(printf '%s' "$dump" | grep -o 'text="[^"]\{1,30\}"' | sort -u | head -12 | tr '\n' ' ')"
    echo "look at:  the server may have emptied the Communities slot (v1 failure mode 4);"
    echo "look at:  with no tab there, S1's 'tap Communities' cannot run before hook 1 (S2)."
    return 1
  fi
  $ADB shell input tap $coords
  sleep 4
  after="$(ui_text)"
  if ! printf '%s' "$after" | grep -q "Search Reddit"; then
    echo "expected: Reddit's search page ('Search Reddit' hint) after tapping Communities"
    echo "found:    no search page 4s after the tap"
    echo "look at:  is *Hide feeds* ON? (Morphe -> Navigation bar -> Hide feeds, as a guest)"
    echo "look at:  adb logcat -d | grep 'onStartTabAttached failure'"
    echo "seen:     $(printf '%s' "$after" | grep -o 'text=\"[^\"]\{1,30\}\"' | sort -u | head -12 | tr '\n' ' ')"
    return 1
  fi
  if feed_markers_present "$after"; then
    echo "expected: the search page before typing shows no feed cards"
    echo "found:    feed action markers in the search-page dump - this needs the owner's eyes"
    echo "look at:  the search zero state; the v2 note says this is an S1 failure"
    return 1
  fi
  return 0
}
check "tap Communities: Reddit's search page opens as a guest, no feed visible" \
  "look at: uiautomator dump, the Hide feeds toggle, logcat" tap_communities_expect_search

back_to_empty_communities_tab() {
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 3
  dump="$(ui_text)"
  if printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: Back leaves the search page"
    echo "found:    the search page is still showing"
    return 1
  fi
  if feed_markers_present "$dump"; then
    echo "expected: the Communities tab body is blank (Discover feed guarded)"
    echo "found:    feed action markers in the dump after Back - a feed is visible"
    return 1
  fi
  if ! $ADB shell pidof "$PACKAGE" >/dev/null 2>&1; then
    echo "expected: the app still running after Back"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  echo "the Communities tab is up with no feed markers; dump left for the owner to eyeball:"
  printf '%s' "$dump" | grep -o 'text=\"[^\"]\{1,30\}\"' | sort -u | head -12 | sed 's/^/  /'
  return 0
}
check "Back from search: empty Communities tab, no Discover feed, no crash" \
  "look at: uiautomator dump and logcat" back_to_empty_communities_tab

log_clean() {
  out="$($ADB logcat -d 2>/dev/null)"
  ! printf '%s' "$out" | grep -q "onStartTabAttached failure" &&
    ! printf '%s' "$out" | grep -q "FATAL EXCEPTION"
}
check "no patch failure and no crash over the whole run" \
  "look at: adb logcat -d for 'onStartTabAttached failure' or 'FATAL EXCEPTION'" log_clean

finish
