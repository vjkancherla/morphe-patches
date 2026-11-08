#!/usr/bin/env bash
# S0 - Baseline: the fork builds and patches Reddit 2026.45.0, unmodified.
# Written from docs/build-plan.md step S0 Check lines. Run via scripts/checkpoint.sh 0.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/env.sh"

describe "Baseline: the fork builds and patches Reddit 2026.45.0, unmodified" <<'EOF'
Proves: the toolchain is green before any product code exists, so S1 onward debugs the
        feature, never the build or the patch pipeline.
How:    runs ./gradlew buildAndroid (the bundle is the exit), then Morphe Desktop patches
        the 2026.45.0 .apkm, and its result file must report success, zero failed patches,
        and "Hide navigation buttons" (which pulls in the Settings machinery) applied.
        Last: the product tree must still show no diff against the base commit.
Needs:  JDK 21 and ANDROID_HOME resolvable (explicit defaults match this machine - verified
        2026-11-08); the .apkm in ~/Downloads; ../tools/morphe-desktop jar; git main at
        the branch point.
EOF

toolchain_present() {
  java -version 2>&1 | head -1
  test -f "$APKM"
}

require "JDK 21 and the 2026.45.0 .apkm are present" "look at: JAVA_HOME, ANDROID_HOME, ~/Downloads/*.apkm" toolchain_present

build_android() {
  ./gradlew buildAndroid
}

# Later checks reuse this build, so a failure here stops the run.
require "./gradlew buildAndroid succeeds (V1)" "look at: the gradle output above; on a clean machine the first run compiles 200+ tasks" build_android

check "patch bundles produced by buildAndroid" "look at: patches/build/libs/ (gradle :patches:buildAndroid writes it)" test -f "$BUNDLE"

patch_apk() {
  java -jar ../tools/morphe-desktop-2.1.1-all.jar patch \
    -p "$BUNDLE" \
    -o "$OUT_DIR/patched.apk" \
    -r "$OUT_DIR/result.json" \
    "$APKM"
}

require "morphe-desktop patches the .apkm clean (V2, mechanical half)" \
  "look at: the jar output above and $OUT_DIR/result.json; a failed fingerprint names the patch" patch_apk

result_is_clean() {
  python3 -c "
import json
r = json.load(open('$OUT_DIR/result.json'))
assert r['success'], 'result.success is false'
assert not r['failedPatches'], 'failedPatches: %r' % (r['failedPatches'],)
assert 'Hide navigation buttons' in r['appliedPatches'], 'Hide navigation buttons not applied'
"
}

check "result file: success, no failed patch, hide-nav applied" \
  "look at: $OUT_DIR/result.json (appliedPatches/failedPatches keys)" result_is_clean


# The diff base is the commit S0 started on - the branch was created AHEAD of main,
# so the base for "this feature's changes" is the branch tip at S0 start, not main.
# git log -1 feat/hide-home-feed at S0 start: 6450ea3a3 (verified, worktree clean).
base="${S0_BASE:-6450ea3a3}"
diff_stat="$(git diff --stat "$base" -- patches/ extensions/ | wc -l | tr -d ' ')"
check_eq "no product diff against base, patches/ and extensions/ only (V3)" \
  "look at: git diff --stat $base.. -- patches/ extensions/" 0 "$diff_stat"

finish
