#!/usr/bin/env bash
# S2 - Hooks 2-3 on the device: the setting OFF behaves stock, ON keeps the start screen.
# Written from docs/build-plan.md step S2 Check lines and the third amendment. Run via
# scripts/checkpoint.sh 2.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "S2: the OFF setting is stock; ON keeps Home on the empty start screen" <<'EOF'
Proves: with *Hide feeds* OFF, the app is stock - a cold start renders the Home feed, and
        the guest drawer's Discover/Popular rows render normally (V17). With it ON, the
        cold start opens search by itself (hook 5) and a Home tap opens search with the
        Communities screen and its top bar attached underneath after Back (hooks 2-3 +
        hook 6, V16's Home route). No feed when ON, no crash anywhere.
How:    rebuilds, re-patches and ALWAYS installs the freshly patched build with `install -r`
        (data kept). Works the phone through uiautomator dumps; the *Hide feeds* toggle is
        driven through Morphe settings (Communities top bar menu -> Morphe -> scroll to the
        toggle) and verified behaviorally by the cold starts, never by trusting the tap.
Needs:  the phone attached over adb and UNLOCKED; *Hide feeds* already ON as a guest
        (Morphe -> Navigation bar -> Hide feeds). No login is used or expected. Guest mode
        only; subreddit pages the check opens deliberately are exempt from feed markers.
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

phone_unlocked() {
  policy="$($ADB shell dumpsys window policy 2>/dev/null)"
  if printf '%s' "$policy" | grep -q "mIsShowing=true"; then
    echo "expected: the phone unlocked, with no keyguard showing"
    echo "found:    the keyguard is showing"
    echo "look at:  unlock the phone yourself, keep it unlocked, then re-run scripts/checkpoint.sh 2"
    return 1
  fi
  return 0
}
require "the phone is unlocked by the owner (adb cannot clear its lock screen)" \
  "look at: the keyguard message above" phone_unlocked

confirm_install_sheet() {
  for attempt in $(seq 1 18); do
    $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
    result="$($ADB shell cat /sdcard/window_dump.xml 2>/dev/null | python3 -c "
import re, sys
xml = sys.stdin.read()
pat = re.compile(r'text=\"Continue installation\"[^>]*bounds=.{0,20}?\\[(\d+),(\d+)\\]\\[(\d+),(\d+)\\]')
m = pat.search(xml)
print((int(m.group(1))+int(m.group(3)))//2, (int(m.group(2))+int(m.group(4)))//2) if m else ''
")" || true
    if [ -n "$result" ]; then $ADB shell input tap $result; fi
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
  "look at: adb install output above" install_freshly_patched_build

ui_text() {
  $ADB shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1
  $ADB shell cat /sdcard/window_dump.xml 2>/dev/null
}

ui_text_retried() {
  for attempt in 1 2 3; do
    dump="$(ui_text)"
    [ -n "$dump" ] && grep -q 'bounds="' <<<"$dump" && { printf '%s' "$dump"; return 0; }
    sleep 2
  done
  printf '%s' "$dump"
}

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

cold_start() {
  $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB shell am force-stop "$PACKAGE" >/dev/null 2>&1
  sleep 1
  activity="$($ADB shell cmd package resolve-activity --brief "$PACKAGE" 2>/dev/null | tail -1 | tr -d '\r')"
  [ -n "$activity" ] || activity="$PACKAGE/launcher.default"
  $ADB shell am start -n "$activity" >/dev/null 2>&1
  for attempt in $(seq 1 20); do
    $ADB shell dumpsys window 2>/dev/null | grep -q "mCurrentFocus=.*$PACKAGE" && break
    sleep 1
  done
  sleep 3
}

feed_markers_present() {
  printf '%s' "$1" | grep -Eq 'content-desc="(Upvote|Downvote|Comment|Share)"|text="(Upvote|Downvote|Share)"'
}

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

tap_node() {  # <dump> <label>
  coords="$(node_center "$1" "$2")"
  [ -n "$coords" ] && $ADB shell input tap $coords
}

close_search_with_back() {
  # Only while the dump is the search PAGE: the stock home with the setting OFF also
  # shows a "Search Reddit" pill, but it carries a "Log in" chip the search page (as a
  # guest) never shows - Back from the stock home would leave the app.
  for round in 1 2 3; do
    dump="$(ui_text)"
    if ! is_search_page "$dump"; then return 0; fi
    $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
    sleep 3
  done
  return 1
}

is_search_page() {  # <dump>
  printf '%s' "$1" | grep -q "Search Reddit" &&
    ! printf '%s' "$1" | grep -Eqi '(text|content-desc)="[^"]*log ?in[^"]*"'
}

bar_top_present() {  # <dump>
  printf '%s' "$1" | grep -Eq 'Open community menu|text="search on Reddit"|(text|content-desc)="Search"'
}

process_alive() {
  $ADB shell pidof "$PACKAGE" >/dev/null 2>&1
}

row_bounds() {  # <dump> <label> -> x1 y1 x2 y2 of the node's box, or empty
  printf '%s' "$1" | LABEL="$2" python3 -c "
import os, re, sys
xml = sys.stdin.read()
label = os.environ['LABEL']
for node in xml.split('<node ')[1:]:
  t = re.search(r'\btext=\"([^\"]*)\"', node)
  c = re.search(r'\bcontent-desc=\"([^\"]*)\"', node)
  for val in (t.group(1) if t else '', c.group(1) if c else ''):
    if val and (val == label or val.startswith(label)):
      b = re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', node)
      if b:
        print(b.group(1), b.group(2), b.group(3), b.group(4))
        sys.exit(0)
"
}

# The Morphe settings entry: top-bar menu (a lag a fixed sleep misses) -> Morphe.
open_morphe_entry() {
  close_search_with_back
  dump="$(ui_text_retried)"
  if ! bar_top_present "$dump"; then
    coords="$(node_center "$dump" "Home")"
    [ -n "$coords" ] && { $ADB shell input tap $coords; sleep 4; }
    if ! close_search_with_back; then
      echo "expected: a Home tap opens search and Back leaves it (hook 6)"
      echo "found:    the search page stayed up through three rounds of Back"
      return 1
    fi
    dump="$(wait_for_ui 'Open community menu|text="search on Reddit"|(text|content-desc)="Search"' 12)"
    if ! bar_top_present "$dump"; then
      echo "expected: the Communities top bar after a Home tap flow"
      echo "found:    no top-bar node in the dump"
      echo "seen:     $(dump_texts "$dump")"
      return 1
    fi
  fi
  tap_node "$dump" "Open community menu"
  menu="$(wait_for_ui '(text|content-desc)="[^"]*[Mm]orphe[^"]*"' 15)"
  if ! printf '%s' "$menu" | grep -Eiq '(text|content-desc)="[^"]*morphe[^"]*"'; then
    echo "expected: the Communities top bar's menu holding the Morphe entry"
    echo "found:    no Morphe node after opening the menu"
    echo "seen:     $(dump_texts "$menu")"
    $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
    return 1
  fi
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  dump="$(ui_text_retried)"
  tap_node "$dump" "Open community menu"
  menu="$(wait_for_ui '(text|content-desc)="[^"]*[Mm]orphe[^"]*"' 15)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  tap_node "$menu" "Morphe"
  sleep 3
  return 0
}

# Toggle a Morphe setting by its title, scrolling if the row is off screen. Taps the row's
# own switch (a checkable node in the title's band - confirmed truthful: checked flips with
# the tap) and re-taps until it reads the desired state or the retries run out.
set_morphe_toggle() {  # <title> <desired true|false>
  for attempt in 1 2 3 4 5; do
    dump="$(ui_text_retried)"
    rb="$(row_bounds "$dump" "$1")"
    if [ -n "$rb" ]; then
      printf '%s' "$rb" | {
        read -r x1 y1 x2 y2
        target=$(printf '%s' "$dump" | python3 -c "
import re, sys
xml = sys.stdin.read()
y1, y2 = $y1, $y2
best = ''
for node in xml.split('<node ')[1:]:
  if 'checkable=\"true\"' not in node:
    continue
  b = re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', node)
  if not b:
    continue
  yc = (int(b.group(2)) + int(b.group(4))) // 2
  if y1 <= yc <= y2:
    best = str((int(b.group(1)) + int(b.group(3))) // 2) + ' ' + str(yc)
print(best)
")
        if [ -n "$target" ]; then
          $ADB shell input tap $target
        else
          $ADB shell input tap $(( (x1 + x2) / 2 )) "$(( (y1 + y2) / 2 ))"
        fi
        sleep 2
      }
      state="$(row_switch_state "$1")"
      if [ "$state" = "$2" ]; then
        echo "$state"
        return 0
      fi
      echo "tap $attempt left '$1' at checked=${state:-unreadable} (wanted $2), tapping again" >&2
      if [ "$attempt" -eq 5 ]; then
        echo "$state"
        return 1
      fi
    else
      $ADB shell input swipe 540 1800 540 700 300 >/dev/null 2>&1
      sleep 2
    fi
  done
  echo "expected: a '$1' row visible in Morphe settings after scrolling"
  echo "found:    the row never appeared in five dumps"
  return 1
}

row_switch_state() {  # <title>
  dump="$(ui_text_retried)"
  printf '%s' "$dump" | python3 -c "
import re, sys
xml = sys.stdin.read()
label = '$1'
state = '?'
for chunk in xml.split('<node ')[1:]:
  t = re.search(r'\btext=\"([^\"]*)\"', chunk)
  c = re.search(r'\bcontent-desc=\"([^\"]*)\"', chunk)
  val = (t.group(1) if t else '') or (c.group(1) if c else '')
  if val.startswith(label):
    yb = re.search(r'bounds=\"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]\"', chunk)
    if not yb:
      continue
    y1, y2 = int(yb.group(2)), int(yb.group(4))
    for s in xml.split('<node ')[1:]:
      if 'checkable=\"true\"' not in s:
        continue
      b = re.search(r'bounds=\"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]\"', s)
      if not b:
        continue
      sy1, sy2 = int(b.group(2)), int(b.group(4))
      cy = (sy1 + sy2) // 2
      if y1 <= cy <= y2:
        chk = re.search(r'checked=\"([^\"]*)\"', s)
        state = chk.group(1) if chk else '?'
        break
    break
print(state)
"
}

# 1) Make sure the feature is ON before verifying its behavior --------------------------
#    (A prior checkpoint run may have left *Hide feeds* OFF; the stock home's own menu
#    shows a Morphe entry, so the turn-on path is reachable from wherever the app is.)

ensure_feature_on() {
  cold_start
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  dump="$(ui_text_retried)"
  if is_search_page "$dump"; then
    echo "Hide feeds already ON: cold start lands on search"
    return 0
  fi
  if ! printf '%s' "$dump" | grep -q "Log in"; then
    echo "expected: either the search page (ON) or the stock guest home (OFF) after cold start"
    echo "found:    neither marker in the dump -"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  note "Hide feeds found OFF at entry - turning it ON through the stock home's menu"
  tap_node "$dump" "Open community menu"
  menu="$(wait_for_ui '(text|content-desc)="[^"]*[Mm]orphe[^"]*"' 15)"
  if ! printf '%s' "$menu" | grep -Eiq '(text|content-desc)="[^"]*morphe[^"]*"'; then
    echo "expected: the menu holding the Morphe entry"
    echo "found:    no Morphe node -"
    echo "seen:     $(dump_texts "$menu")"
    $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
    return 1
  fi
  tap_node "$menu" "Morphe"
  sleep 4
  if ! state="$(set_morphe_toggle "Hide feeds" true)"; then
    echo "expected: the Hide feeds switch flipped to checked=true"
    echo "found:    the tap did not flip it: $state"
    return 1
  fi
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  cold_start
  dump="$(ui_text_retried)"
  if ! is_search_page "$dump"; then
    echo "expected: after turning Hide feeds ON, a cold start opens the search page"
    echo "found:    no search page -"
    echo "seen:     $(dump_texts "$dump")"
    echo "look at:  adb logcat -d | grep 'getStartTab failure\\|onStartTabAttached failure\\|openSearchPage failure'"
    return 1
  fi
  echo "Hide feeds ON: cold start lands on search"
  return 0
}
require "Hide feeds ON at entry (flipped through the stock home's menu when found OFF)" ensure_feature_on

cold_start_opens_search() {
  cold_start
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  dump="$(ui_text_retried)"
  if ! printf '%s' "$dump" | grep -q "Search Reddit"; then
    echo "expected: the search page opens by itself on cold start (hook 5)"
    echo "found:    no search page in the cold-start dump"
    echo "bar:      $(bar_summary "$dump")"
    echo "seen:     $(dump_texts "$dump")"
    echo "look at:  is *Hide feeds* ON? (Morphe -> Navigation bar -> Hide feeds, as a guest)"
    return 1
  fi
  if login_markers_present "$dump"; then
    echo "expected: search opens with no login prompt (the app must work as a guest)"
    echo "found:    a login call-to-action in the search-page dump - stopping for the owner:"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if feed_markers_present "$dump"; then
    echo "expected: the search page shows no feed cards"
    echo "found:    feed action markers in the search-page dump - this needs the owner's eyes"
    return 1
  fi
  return 0
}
check "V5 re-run (setting ON): cold start opens the search page, no login, no feed" \
  "look at: uiautomator dump, logcat" cold_start_opens_search

# 2) V16's Home route: a Home tap opens search; the Communities top bar underneath ------

home_tap_lands_communities() {
  # The cold-start search covers the bar; close it first (search opens again from the tap).
  if ! close_search_with_back; then
    echo "expected: Back leaves the search page"
    echo "found:    the search page stayed up through three rounds of Back"
    return 1
  fi
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  dump="$(ui_text_retried)"
  coords="$(node_center "$dump" "Home")"
  if [ -z "$coords" ]; then
    echo "expected: a Home node in the bar to tap"
    echo "found:    none -"
    echo "bar:      $(bar_summary "$dump")"
    return 1
  fi
  $ADB shell input tap $coords
  sleep 4
  if ! close_search_with_back; then
    echo "expected: Back leaves the search page opened by the Home tap"
    echo "found:    the search page stayed up through three rounds of Back"
    return 1
  fi
  dump="$(wait_for_ui 'Open community menu|text="search on Reddit"|(text|content-desc)="Search"' 12)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if feed_markers_present "$dump"; then
    echo "expected: the Communities top bar over an empty page after the Home tap flow"
    echo "found:    feed action markers in the dump - a feed is visible"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  if ! printf '%s' "$dump" | grep -Eq 'Open community menu|text="search on Reddit"|(text|content-desc)="Search"'; then
    echo "expected: the Communities top bar over an empty page (hooks 2-3 keep this route)"
    echo "found:    no top-bar node in the dump"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  echo "Home tap -> search -> Back: the Communities top bar is over an empty page"
  return 0
}
check "V16 Home route: Home tap opens search; Back shows the Communities top bar, no feed" \
  "look at: uiautomator dump" home_tap_lands_communities

# 3) V17: the setting OFF is stock ------------------------------------------------------

toggle_off_via_morphe() {
  if ! open_morphe_entry; then return 1; fi
  if ! state="$(set_morphe_toggle "Hide feeds" false)"; then
    echo "expected: the Hide feeds switch flipped to checked=false"
    echo "found:    the tap did not flip it: $state"
    return 1
  fi
  # Leave the settings screen.
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  echo "Hide feeds OFF (switch row read checked=false)"
  return 0
}

restore_on_via_morphe() {
  if ! open_morphe_entry; then return 1; fi
  if ! state="$(set_morphe_toggle "Hide feeds" true)"; then
    echo "expected: the Hide feeds switch flipped to checked=true"
    echo "found:    the tap did not flip it: $state"
    return 1
  fi
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  echo "Hide feeds back ON (switch row read checked=true)"
  return 0
}

# This build's guest screens carry almost no a11y text (a richly rendered home dumps ~80+
# nodes with only chrome labels), so "renders normally" reads the SCREEN, not the dump:
# distinct sampled pixel colors in the content band - a blank page scores in the hundreds,
# rendered feed content in the thousands (measured 2026-11-10).
content_pixel_score() {
  $ADB shell screencap -p /sdcard/cc.png >/dev/null 2>&1
  $ADB pull /sdcard/cc.png /tmp/ckpt_cc.png >/dev/null 2>&1 || { echo 0; return; }
  python3 - <<'PY'
import zlib, struct
try:
    data = open('/tmp/ckpt_cc.png','rb').read()
    pos = 8; idat = b''; w = h = None; bitdepth = colortype = None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        if typ == b'IHDR':
            w, h, bitdepth, colortype = struct.unpack('>IIBB', data[pos+8:pos+18])
        elif typ == b'IDAT':
            idat += data[pos+8:pos+8+ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    channels = {0:1, 2:3, 3:1, 4:2, 6:4}[colortype]
    stride = w*channels
    out = bytearray(h*stride); prev = bytearray(stride); p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(channels, stride): line[i] = (line[i]+line[i-channels])&255
        elif f == 2:
            for i in range(stride): line[i] = (line[i]+prev[i])&255
        elif f == 3:
            for i in range(stride):
                a = line[i-channels] if i>=channels else 0
                line[i] = (line[i]+((a+prev[i])>>1))&255
        elif f == 4:
            for i in range(stride):
                a = line[i-channels] if i>=channels else 0
                c = prev[i-channels] if i>=channels else 0
                b = prev[i]; pp = a+b-c
                pa,pb,pc = abs(pp-a),abs(pp-b),abs(pp-c)
                pr = a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i] = (line[i]+pr)&255
        out[y*stride:(y+1)*stride] = line
        prev = line
    from collections import Counter
    cnt = Counter()
    for y in range(300, h-360, 10):
        for x in range(0, w, 10):
            o = y*stride + x*channels
            if channels >= 3:
                cnt[bytes((out[o],out[o+1],out[o+2]))] += 1
    print(len(cnt))
except Exception:
    print(0)
PY
}

off_stock_home() {
  if ! toggle_off_via_morphe; then return 1; fi
  cold_start
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  sleep 5
  if ! process_alive; then
    echo "expected: the stock app alive after cold start"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  dump="$(ui_text_retried)"
  if ! printf '%s' "$dump" | grep -q "Log in"; then
    echo "expected: the stock guest home chrome (search pill, Log in chip)"
    echo "found:    no guest chrome in the dump -"
    echo "seen:     $(dump_texts "$dump")"
    return 1
  fi
  score="$(content_pixel_score)"
  if [ "$score" -lt 800 ]; then
    echo "expected: the stock Home feed rendering its cards (pixel score $((score)))"
    echo "found:    the content band is essentially blank (score ${score}, hope >= 800);"
    echo "          a blank page screenshotted here with the toggle OFF is a V17 fail"
    return 1
  fi
  echo "stock Home feed is rendering (V17 OFF): guest chrome present, pixel score ${score}"
  return 0
}
check "V17 OFF, Home: the stock feed renders after cold start" "look at: pixel score and dump" off_stock_home

off_stock_drawer_rows() {
  # From the stock home: its hamburger opens the communities menu with the Popular row.
  dump="$(ui_text_retried)"
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  tap_node "$dump" "Open community menu"
  menu="$(wait_for_ui '(text|content-desc)="[^"]*Popular[^"]*"' 10)"
  if ! printf '%s' "$menu" | grep -Eq '(text|content-desc)="[^"]*Popular[^"]*"'; then
    echo "expected: the menu with a Popular row (V17 OFF)"
    echo "found:    no Popular row in the dump -"
    echo "seen:     $(dump_texts "$menu")"
    return 1
  fi
  if ! printf '%s' "$menu" | grep -Eqi '(text|content-desc)="[^"]*discover[^"]*"'; then
    note "variant: the menu holds no Discover row in this build - Popular is the row exercised"
  fi
  tap_node "$menu" "Popular"
  sleep 10
  require_oops="$(reddit_in_front)" || { echo "$require_oops"; return 1; }
  if ! process_alive; then
    echo "expected: the Popular feed screen keeps the app alive (V17 OFF)"
    echo "found:    the process is gone; look for a crash in logcat"
    return 1
  fi
  score="$(content_pixel_score)"
  if [ "$score" -lt 800 ]; then
    echo "expected: the Popular feed renders as a guest (pixel score $((score)))"
    echo "found:    the content band is essentially blank (score ${score})"
    return 1
  fi
  $ADB shell input keyevent KEYCODE_BACK >/dev/null 2>&1
  sleep 2
  echo "Popular renders normally with the setting OFF (pixel score ${score})"
  return 0
}
check "V17 OFF, Discover/Popular: the menu's Popular row renders normally" \
  "look at: pixel score; the used variant is recorded" off_stock_drawer_rows

restore_on_and_reverify() {
  if ! restore_on_via_morphe; then return 1; fi
  if ! cold_start_opens_search; then return 1; fi
  echo "setting back ON: cold start opens search again (hook 5)"
  return 0
}
check "Hide feeds restored ON: cold start lands on search again" "look at: uiautomator dump" restore_on_and_reverify

# 4) Logs -----------------------------------------------------------------------------

log_clean() {
  out="$($ADB logcat -d 2>/dev/null)"
  ! printf '%s' "$out" | grep -qE '"?(getStartTab|onBottomTabTapped|onStartTabAttached|openSearchPage|filterSearchZeroState) failure' &&
    ! printf '%s' "$out" | grep -q "FATAL EXCEPTION"
}
check "no hook failure and no crash over the whole run (the original-tab path stayed quiet)" \
  "look at: adb logcat -d" log_clean

finish
