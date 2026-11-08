#!/usr/bin/env bash
# S1 - The drawer opens on command (the riskiest assumption).
# Written from docs/build-plan.md step S1 Check lines. Run via scripts/checkpoint.sh 1.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "S1: the drawer opens from the patched route (riskiest assumption)" <<'EOF'
Proves: tapping the Communities tab opens Reddit's own subreddit drawer through the
        injected method - the route the whole design hangs on - and that a fresh,
        un-signed-in install of the patched build boots clean with the setting off.
How:    rebuilds and re-patches (V2 again). On the phone: if Reddit is not already
        patched with this build, it is reinstalled fresh (this wipes the app's data -
        that is the accepted disposable test device). A just-fresh install cold-starts
        and must stay alive with no crash. Then, once the owner has signed in
        (one-time phone step) and turned Morphe -> Navigation bar -> Hide Home feed on,
        this checkpoint taps Communities via uiautomator and asserts the drawer's
        section headers appear on screen.
Needs:  ./gradlew buildAndroid producing the bundle; the 2026.45.0 .apkm; a phone
        attached over adb; for the final check: Reddit signed in with joined
        subreddits and the toggle on.
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
check "result file: success, no failed patch, hide-nav applied" \
  "look at: $OUT_DIR/result.json (appliedPatches/failedPatches)" result_clean

device_attached() {
  $ADB devices | tail -n +2 | grep -c "device$"
}
# The phone is the S1 test bench; without it the rest of this checkpoint cannot run.
require "a phone is attached over adb (waiting for the phone if empty)" \
  "look at: adb devices output above; plug in the test phone with USB debugging on" device_attached

# --- install: fresh only if the installed app is not this patched build ----------

# Marker: this step's injected symbol. A build that carries anything older lacks it and
# gets refreshed (with the one accepted data wipe).
MARKER="patch_openCommunityDrawer"

installed_patched() {
  base="$($ADB shell pm path "$PACKAGE" 2>/dev/null | head -1 | sed 's/package://' | tr -d '\r')"
  [ -n "$base" ] || return 1
  $ADB shell "unzip -o -q $base '*.dex' -d /data/local/tmp/ckpt_dex >/dev/null 2>&1; grep -l '$MARKER' /data/local/tmp/ckpt_dex/*.dex >/dev/null 2>&1"
}

fresh_needed=1
if installed_patched; then
  fresh_needed=0
  note "Installed app already carries this patch - keeping its login and toggle state."
else
  confirm_install_sheet() {
    # ColorOS gates every adb install behind an on-device confirmation sheet; poll and
    # tap it. If it never appears (some builds with install-permission pre-granted),
    # the poll simply times out and the install proceeds on its own.
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
    $ADB shell input swipe 540 1800 540 500 300 >/dev/null 2>&1
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
  require "patched build installed fresh on the phone (wipes its Reddit data - accepted)" \
    "look at: adb install output above" install_fresh
fi

if [ "$fresh_needed" -eq 1 ]; then
  cold_start_off() {
    $ADB logcat -c 2>/dev/null
    $ADB shell am monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 8
    $ADB shell pidof "$PACKAGE" >/dev/null
  }
  check "setting off, fresh cold start: app boots and stays alive" \
    "look at: logcat below for FATAL EXCEPTION; a crash here is packaging, not the feature" cold_start_off

  crash_free() {
    out="$($ADB logcat -d 2>/dev/null)"
    ! printf '%s' "$out" | grep -q "onStartTabAttached failure" &&
    ! printf '%s' "$out" | grep -q "FATAL EXCEPTION"
  }
  check "fresh cold start logged no patch failure and no crash" \
    "look at: adb logcat -d for 'onStartTabAttached failure' or 'FATAL EXCEPTION'" crash_free
fi

bring_to_front() {
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB shell input keyevent 82 >/dev/null 2>&1
  $ADB shell am monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 3
}

ui_text() {
  $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
  $ADB shell cat /sdcard/window_dump.xml 2>/dev/null
}

logged_out() {
  dumpdir="$(bring_to_front; ui_text)"
  printf '%s' "$dumpdir" | grep -Eq "Log in|Sign up|Continue with Google|Create account" && echo yes || echo no
}

if [ "$(logged_out)" = "yes" ]; then
  note "The patched app is fresh and logged out. One-time phone step, no other way around it:"
  note "-> sign in on the phone, join/verify a subreddit or two in the drawer, then Morphe ->"
  note "-> Navigation bar -> Hide Home feed = ON. Then say 'continue S1' and this re-runs,"
  note "-> keeping the signed-in state (no reinstall happens once the patch is present)."
  signed_in_gate() {
    echo "expected: signed-in Reddit with joined subreddits, Hide Home feed toggled on"
    echo "found:    the log-in screen"
    echo "look at:  RUNBOOK.md 'The phone' section; re-run scripts/checkpoint.sh 1 after signing in"
    return 1
  }
  check "app signed in and set up (owner's one-time phone step)" \
    "look at: the note above" signed_in_gate
  finish
fi

tap_communities_and_assert_drawer() {
  dumpdir="$(bring_to_front; ui_text)"
  coords="$(
    printf '%s' "$dumpdir" | python3 -c "
import re, sys
xml = sys.stdin.read()
pat = re.compile(r'(?:text|content-desc)=\"Communities\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"')
for m in pat.finditer(xml):
    x = (int(m.group(1)) + int(m.group(3))) // 2
    y = (int(m.group(2)) + int(m.group(4))) // 2
    print(x, y)
    break
"
  )"
  if [ -z "$coords" ]; then
    echo "expected: a bottom-bar tab whose label is Communities"
    echo "found:    no such node in the uiautomator dump"
    echo "look at:  $(printf '%s' "$dumpdir" | grep -o 'text=\"[^\"]\{1,40\}\"' | sort -u | head -10)"
    return 1
  fi
  $ADB shell input tap $coords
  sleep 4
  after="$(ui_text)"
  if printf '%s' "$after" | grep -Eq "COMMUNITIES|Favorites|Moderating|Recently Visited"; then
    echo "watch out: drawer visible (section markers found in dump)"
    return 0
  fi
  echo "expected: drawer open (COMMUNITIES/Favorites/Moderating/Recently Visited section in dump)"
  echo "found:    no drawer markers 4s after tapping Communities"
  echo "look at:  Morphe toggle off? (Morphe -> Navigation bar -> Hide Home feed) or the route broke:"
  echo "look at:  adb logcat -d | grep 'onStartTabAttached failure'"
  return 1
}
check "tap Communities: the drawer opens with your signed-in sections" \
  "look at: uiautomator dump; also the Morphe toggle" tap_communities_and_assert_drawer

route_clean() {
  out="$($ADB logcat -d 2>/dev/null)"
  ! printf '%s' "$out" | grep -q "onStartTabAttached failure"
}
check "no 'onStartTabAttached failure' in logcat over the whole run" \
  "look at: adb logcat -d" route_clean

finish
