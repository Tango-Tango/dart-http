#!/usr/bin/env bash
# Build and optionally run old vs guarded OkHttp soak APKs.
#
# Old SHA:     74e326d6fec11b579020b19bff844a728951fa5b
# Guarded SHA: ce1f7251873a2f50c2c7f995d42ee904e6bff93b
#
# Usage:
#   pkgs/ok_http/tool/run_jni_lifetime_soak.sh build
#   pkgs/ok_http/tool/run_jni_lifetime_soak.sh run old [hours]
#   pkgs/ok_http/tool/run_jni_lifetime_soak.sh run guarded [hours]
#   pkgs/ok_http/tool/run_jni_lifetime_soak.sh collect

set -euo pipefail

OLD_SHA=74e326d6fec11b579020b19bff844a728951fa5b
GUARDED_SHA=ce1f7251873a2f50c2c7f995d42ee904e6bff93b
PACKAGE=com.example.ok_http_example
ACTIVITY=com.example.ok_http_example.MainActivity
SOAK_URL="${SOAK_URL:-https://example.com/}"
SOAK_WORKERS="${SOAK_WORKERS:-4}"

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${SOAK_OUT:-/tmp/okhttp-soak-artifacts}"
SOAK_SRC="$ROOT/pkgs/ok_http/example/lib/soak_main.dart"

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

need_adb() {
  command -v adb >/dev/null
  adb get-state >/dev/null
}

copy_soak() {
  local dest="$1/pkgs/ok_http/example/lib/soak_main.dart"
  mkdir -p "$(dirname "$dest")"
  cp "$SOAK_SRC" "$dest"
}

# Same R8 keeps Shine uses. Flutter forces minify on release APKs; JNI
# loads these classes by name, so they must not be stripped.
prepare_example() {
  local example="$1/pkgs/ok_http/example"
  local app="$example/android/app"
  mkdir -p "$app"
  cat >"$app/proguard-rules.pro" <<'EOF'
-keep class com.example.ok_http.** { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keepattributes InnerClasses,EnclosingMethod,Signature
EOF
  local manifest="$app/src/main/AndroidManifest.xml"
  if [[ -f "$manifest" ]] && ! grep -q 'android.permission.INTERNET' "$manifest"; then
    python3 - "$manifest" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
insert = needle + '\n    <uses-permission android:name="android.permission.INTERNET"/>'
if needle not in s:
    raise SystemExit(f'cannot patch INTERNET permission in {p}')
p.write_text(s.replace(needle, insert, 1))
PY
  fi
  python3 - "$app/build.gradle" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if 'proguard-rules.pro' in s:
    raise SystemExit(0)
needle = 'signingConfig = signingConfigs.debug'
insert = (
    'signingConfig = signingConfigs.debug\n'
    '            minifyEnabled true\n'
    '            shrinkResources false\n'
    '            proguardFiles getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"'
)
if needle not in s:
    raise SystemExit(f'cannot patch {p}')
p.write_text(s.replace(needle, insert, 1))
PY
}

apk_has_okhttp() {
  python3 - "$1" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        if name.endswith('.dex'):
            data = z.read(name)
            if b'OkHttpClient' in data:
                raise SystemExit(0)
raise SystemExit(1)
PY
}

build_one() {
  local label="$1" sha="$2" worktree="$3"
  mkdir -p "$worktree"
  if [[ ! -d "$worktree/.git" && ! -f "$worktree/.git" ]]; then
    git -C "$ROOT" worktree add --detach "$worktree" "$sha"
  fi
  copy_soak "$worktree"
  (
    cd "$worktree/pkgs/ok_http/example"
    flutter clean
    flutter pub get
  )
  prepare_example "$worktree"
  (
    cd "$worktree/pkgs/ok_http/example"
    flutter build apk --release \
      --target lib/soak_main.dart \
      --android-skip-build-dependency-validation \
      --dart-define="SOAK_LABEL=$label" \
      --dart-define="SOAK_URL=$SOAK_URL" \
      --dart-define="SOAK_WORKERS=$SOAK_WORKERS"
  )
  local apk="$worktree/pkgs/ok_http/example/build/app/outputs/flutter-apk/app-release.apk"
  local dest="$OUT/$label"
  mkdir -p "$dest"
  cp "$apk" "$dest/app-release.apk"
  printf '%s\n' "$sha" >"$dest/sha.txt"
  local mapping="$worktree/pkgs/ok_http/example/build/app/outputs/mapping/release/mapping.txt"
  if [[ -f "$mapping" ]]; then
    cp "$mapping" "$dest/mapping.txt"
  fi
  if ! apk_has_okhttp "$apk"; then
    log "ERROR: OkHttpClient missing from $label APK dex"
    unzip -Z1 "$apk" | grep -E 'classes|okhttp' || true
    if [[ -f "$dest/mapping.txt" ]]; then
      grep -E 'okhttp3|OkHttpClient' "$dest/mapping.txt" | head || true
    fi
    exit 1
  fi
  unzip -l "$apk" | awk '/lib\/.*\/(libapp|libdartjni)\.so$/ {print $4}' \
    >"$dest/native-libs.txt"
  if command -v llvm-readelf >/dev/null; then
    unzip -p "$apk" lib/arm64-v8a/libapp.so >"$dest/libapp.so" || true
    unzip -p "$apk" lib/arm64-v8a/libdartjni.so >"$dest/libdartjni.so" || true
    llvm-readelf -n "$dest/libapp.so" 2>/dev/null | awk '/Build ID/ {print}' \
      >"$dest/libapp.buildid" || true
    llvm-readelf -n "$dest/libdartjni.so" 2>/dev/null | awk '/Build ID/ {print}' \
      >"$dest/libdartjni.buildid" || true
  fi
  log "built $label -> $dest/app-release.apk"
}

cmd_build() {
  mkdir -p "$OUT"
  build_one old "$OLD_SHA" "$OUT/worktrees/old"
  build_one guarded "$GUARDED_SHA" "$OUT/worktrees/guarded"
}

install_label() {
  local label="$1"
  local apk="$OUT/$label/app-release.apk"
  test -f "$apk"
  adb install -r "$apk"
}

start_soak() {
  adb shell svc power stayon true || true
  adb logcat -c || true
  adb shell am force-stop "$PACKAGE" || true
  adb shell am start -n "$PACKAGE/$ACTIVITY"
}

collect_now() {
  local label="${1:-current}"
  local dest="$OUT/runs/${label}-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$dest"
  adb logcat -d >"$dest/logcat.txt" || true
  adb logcat -d -s flutter:I flutter:E AndroidRuntime:E DEBUG:F libc:F \
    >"$dest/logcat-crash.txt" || true
  adb shell dumpsys dropbox --print data_app_native_crash \
    >"$dest/dropbox-native.txt" 2>/dev/null || true
  grep -E 'SOAK label=|F DEBUG|Fatal signal|libdartjni' "$dest/logcat.txt" \
    >"$dest/highlights.txt" || true
  log "collected $dest"
}

cmd_run() {
  local label="$1"
  local hours="${2:-8}"
  need_adb
  install_label "$label"
  start_soak
  log "running $label for ${hours}h; USB stay-awake enabled"
  local seconds=$((hours * 3600))
  local step=300
  local elapsed=0
  while (( elapsed < seconds )); do
    sleep "$step"
    elapsed=$((elapsed + step))
    log "$label elapsed=${elapsed}s"
    if ! adb shell pidof "$PACKAGE" >/dev/null; then
      log "$label process died"
      collect_now "$label-crash"
      exit 2
    fi
  done
  collect_now "$label-complete"
}

cmd="${1:-}"
case "$cmd" in
  build) cmd_build ;;
  run)
    shift
    cmd_run "${1:?old|guarded}" "${2:-8}"
    ;;
  collect) collect_now "${2:-manual}" ;;
  *)
    echo "Usage: $0 build | run old|guarded [hours] | collect" >&2
    exit 64
    ;;
esac
