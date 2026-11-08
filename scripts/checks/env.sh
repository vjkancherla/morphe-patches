# Shared environment for all checkpoints. Sourced by scripts/checks/*.sh, never run.
# Runs from the project root only - that is the contract for checkpoint invocations
# ("scripts/checkpoint.sh <N>"), in bash or zsh alike.

if [ ! -f "scripts/checks/env.sh" ]; then
  echo "FAIL: checkpoints run from the project root only (pwd is $(pwd))" >&2
  return 124 2>/dev/null || exit 124
fi

JAVA_DIR="/opt/homebrew/opt/openjdk@21"
if [ -z "${JAVA_HOME:-}" ] && [ -d "$JAVA_DIR" ]; then
  export JAVA_HOME="$JAVA_DIR"
fi
if [ -z "${ANDROID_HOME:-}" ]; then
  export ANDROID_HOME="$(pwd)/../android-sdk"
fi
export PATH="$ANDROID_HOME/platform-tools:$PATH"

ADB=adb
APKM="$HOME/Downloads/com.reddit.frontpage_2026.45.0-2645021_3arch_6dpi_23lang_2df4a8b8d38ac6d88146bb8c2f9685c1_apkmirror.com.apkm"
BUNDLE="patches/build/libs/patches-2.1.0.mpp"
OUT_DIR="build/ckpt"
PACKAGE="com.reddit.frontpage"
