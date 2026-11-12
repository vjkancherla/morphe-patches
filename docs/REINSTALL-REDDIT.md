# Reinstall Reddit on the phone

How to put the patched Reddit app back on the phone if it gets deleted, uninstalled, or
wiped. No root, no re-login, no Play Store version - the app is a sideloaded APK built from
this repo.

**Assumption:** this Mac still has the workspace at
`~/Downloads/Devops-Projects/morphe-reddit/` (the repo, the Android SDK, the `morphe-desktop`
jar, and ideally the Reddit 2026.45.0 `.apkm`). If the Mac itself is gone, see
[If the workspace is gone](#6-if-the-workspace-is-gone).

---

## 0. The short version

Phone unlocked, USB debugging on, plugged in:

```bash
cd ~/Downloads/Devops-Projects/morphe-reddit/morphe-patches

# 1. If the existing patched APK is still there, install it
../android-sdk/platform-tools/adb install -r build/ckpt/patched.apk

# 2. If it is missing, rebuild it first (section 4), then install
```

Then on the phone:

1. Open Reddit.
2. Hamburger / community menu -> **Morphe** -> **Navigation bar**.
3. Turn **Hide feeds** ON.
4. Optional: turn **Hide Inbox button** ON.
5. Close and reopen the app - the search page should open by itself.

That is the whole recovery in the normal case. The rest of this file explains each step and
what to do when it fails.

---

## 1. Before you start

| Need | How to check |
|---|---|
| Phone connected and unlocked | `../android-sdk/platform-tools/adb devices` shows `<serial>\tdevice` |
| USB debugging enabled | Settings -> Developer options -> USB debugging |
| This Mac trusted by the phone | Tap **Allow** on the phone's "Allow USB debugging?" prompt |
| JDK 21 for a rebuild | `source ~/.zshrc`, then `java -version` shows 21.x |
| The 2026.45.0 `.apkm` for a rebuild | `ls ~/Downloads/*.apkm` |
| ~200 MB free on the phone | APK is about 160 MB |

The package name is `com.reddit.frontpage`. The patched app has the **same package name** as
the Play Store app but a **different signing key**, which is why an uninstall is sometimes
needed (section 5).

---

## 2. Fast path - reinstall the existing patched APK

Use this when `build/ckpt/patched.apk` exists. It is the normal case and takes under a
minute.

```bash
cd ~/Downloads/Devops-Projects/morphe-reddit/morphe-patches
ls -lh build/ckpt/patched.apk
../android-sdk/platform-tools/adb devices
../android-sdk/platform-tools/adb install -r build/ckpt/patched.apk
```

- `-r` means "reinstall, keep data". Use it whenever the patched build is already installed;
  it preserves the Hide feeds toggle and the guest state.
- If the app was deleted, there is no data to keep; `-r` still works and simply installs.
- Watch the phone: ColorOS may ask **Continue installation**, then show an
  **Installed / Version / Close** sheet. Accept it, then close it.
- If `adb install` says `Success`, go to [section 3](#3-turn-hide-feeds-back-on).

If the APK is missing (`build/` is gitignored and can be cleaned), rebuild it with
[section 4](#4-rebuild-from-source).

---

## 3. Turn Hide feeds back on

A fresh install starts with the feature **off** - without this step the app is stock Reddit,
feed and all. App data only survives `install -r`; an uninstall wipes it.

1. Open Reddit. The *Start as guest* patch skips the login wall.
2. Open the left drawer / hamburger menu and tap **Morphe**.
   - On the stock home the hamburger is the menu on the top left.
   - If the feature is already on and you are on the Communities screen, use the top bar's
     menu -> **Morphe**.
3. Go to **Navigation bar**.
4. Turn **Hide feeds** ON.
5. Optional: turn **Hide Inbox button** ON.
6. Force-stop and reopen the app.

Verify:

- Cold start opens Reddit's **search page by itself**. No login prompt.
- Type a subreddit, open it, press Back - you return to search.
- Tap the bottom bar's **Home** - search opens again; Back shows the empty screen with the
  Communities top bar.
- The top bar's menu still reaches **Morphe**.
- No feed appears at any point.

If any of that is wrong, see [section 5](#5-troubleshooting).

---

## 4. Rebuild from source

Use this when `build/ckpt/patched.apk` is missing, or you want the latest source changes.

### 4.1 Build the patch bundle

```bash
source ~/.zshrc
cd ~/Downloads/Devops-Projects/morphe-reddit/morphe-patches
./gradlew buildAndroid
```

Takes a few minutes on the first run. Output:
`patches/build/libs/patches-2.1.0.mpp`.

### 4.2 Patch the 2026.45.0 APKM

```bash
APKM="$HOME/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm"

java -jar ../tools/morphe-desktop-2.1.1-all.jar patch \
  -p patches/build/libs/patches-2.1.0.mpp \
  -o build/ckpt/patched.apk \
  -r build/ckpt/result.json \
  "$APKM"
```

Check the result before installing:

```bash
python3 -c "
import json
r = json.load(open('build/ckpt/result.json'))
print('success:', r['success'])
print('failed:', r['failedPatches'])
print('hide-nav applied:', 'Hide navigation buttons' in r['appliedPatches'])
"
```

You need `success: True`, an empty `failed: []`, and `hide-nav applied: True`. If a
fingerprint misses, **do not install** - the patch is not what this repo built.

### 4.3 Install

```bash
../android-sdk/platform-tools/adb install -r build/ckpt/patched.apk
```

Then [section 3](#3-turn-hide-feeds-back-on). Note that a rebuild uses the same signing key
as the previous patched build, so `install -r` updates in place and keeps the toggle.

### 4.4 Keep a copy

`build/` is gitignored and disposable. Copy the good APK somewhere durable:

```bash
mkdir -p ~/Downloads/reddit-patched
cp build/ckpt/patched.apk ~/Downloads/reddit-patched/patched-reddit-2026.45.0.apk
```

---

## 5. Troubleshooting

### Install problems

| Message | Cause | Fix |
|---|---|---|
| `adb: no devices/emulators found` | Not connected, USB debugging off, or cable is charge-only | Replug, enable USB debugging, unlock the phone |
| `device unauthorized` | The Mac has not been trusted | Tap **Allow** on the phone, or revoke/re-authorize USB debugging |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Play Store Reddit is installed (different signature) | `../android-sdk/platform-tools/adb uninstall com.reddit.frontpage`, then install. The toggle resets |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | The installed build has a higher version code | Uninstall first, then install |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Phone is full | Free space (about 350 MB during install), retry |
| Install hangs with no output | ColorOS confirmation sheet is waiting | Look at the phone and tap **Continue installation** |
| `Success` but the app looks stock | Hide feeds toggle is off | [Section 3](#3-turn-hide-feeds-back-on) |

### Build/patch problems

| Symptom | Fix |
|---|---|
| `./gradlew` fails immediately | `source ~/.zshrc`; `java -version` must be 21 |
| `ANDROID_HOME` not set | `source ~/.zshrc`, or export `ANDROID_HOME=~/Downloads/Devops-Projects/morphe-reddit/android-sdk` |
| The `.apkm` is missing | Re-download the **2026.45.0** APKM from APKMirror: universal, 120-480 dpi, Android 12L+, versionCode `2645021`. The version must match; other versions may fail fingerprints |
| `failedPatches` is not empty | Wrong APKM version, or source and bundle are out of sync. Rebuild and repatch; do not install |
| `build/ckpt/patched.apk` not created | Read the jar output above; a failed fingerprint names the patch |

### Behaviour problems

| Symptom | Likely cause | Fix |
|---|---|---|
| Cold start still shows the feed | Toggle off | Turn **Hide feeds** ON, force-stop, reopen |
| Search does not auto-open | Toggle off, or stale process | Force-stop the app and reopen; re-check the toggle |
| Morphe menu not found | Hide feeds is ON and you are on the blank guarded screen without the top bar | Tap the bar's **Home** once; after Back the Communities top bar carries the menu |
| Trending still shows on the search page | Known and accepted (V20) | Nothing to fix; the owner accepted this |
| Play Store updates Reddit and breaks it | Store replaced the patched app | Turn off auto-update for Reddit in Play Store, then reinstall per this file |
| Login wall appears | You installed plain Reddit, not this patched APK | Reinstall the patched APK |

---

## 6. If the workspace is gone

This Mac has the only copy of the feature work. The branch `feat/hide-home-feed` is **local
only** - it was never pushed to `origin`.

To be safe against a lost laptop, keep these three things:

1. `build/ckpt/patched.apk` (the ready-to-install app).
2. The 2026.45.0 `.apkm`.
3. A copy of this repo **with the feature branch**, or push the branch with the owner's
   consent.

If you only lose the phone app, none of this matters - sections 2-3 are enough.

To rebuild from a fresh clone you would need:

- this repo at the `feat/hide-home-feed` commit (or the branch pushed/merged),
- JDK 21,
- an Android SDK (or the existing `android-sdk/` folder),
- `morphe-desktop-2.1.1-all.jar`,
- the exact Reddit 2026.45.0 `.apkm`.

---

## 7. What not to do

- Do not install the Play Store version over the patched one; the signatures differ.
- Do not hand-edit the APK or the `.mpp` bundle.
- Do not install a patch run whose `result.json` has `success: false` or a non-empty
  `failedPatches`.
- Do not delete `build/ckpt/patched.apk` until you have copied it somewhere durable.
- Do not commit the APK to git (it is gitignored for a reason - about 160 MB).

---

## Appendix - exact paths

| Item | Path |
|---|---|
| Repo | `~/Downloads/Devops-Projects/morphe-reddit/morphe-patches` |
| adb | `~/Downloads/Devops-Projects/morphe-reddit/android-sdk/platform-tools/adb` |
| Patch bundle | `patches/build/libs/patches-2.1.0.mpp` |
| Patched APK | `build/ckpt/patched.apk` |
| Patch result | `build/ckpt/result.json` |
| Morphe Desktop jar | `../tools/morphe-desktop-2.1.1-all.jar` |
| APKM | `~/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm` |
| Package name | `com.reddit.frontpage` |
