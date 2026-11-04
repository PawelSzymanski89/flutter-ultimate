#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Deterministic Static Code Audit (POSIX Bash)
# ==============================================================================
set -euo pipefail

TARGET_PATH="${1:-.}"
JSON_MODE=false
STRICT_MODE=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --strict) STRICT_MODE=true ;;
  esac
done

TARGET_DIR="$(cd "$TARGET_PATH" && pwd)"
FINDINGS=()

add_finding() {
  local file="$1"
  local line="$2"
  local severity="$3"
  local trap_id="$4"
  local message="$5"
  local rel_file="${file#$TARGET_DIR/}"
  FINDINGS+=("$severity|$trap_id|$rel_file|$line|$message")
}

# 1. Scan Dart Files
while IFS= read -r file; do
  [[ "$file" =~ (\.dart_tool|build|\.git|\.g\.dart|\.freezed\.dart) ]] && continue

  line_num=0
  while IFS= read -r line; do
    ((line_num++))

    # P08: MediaQuery.of() instead of MediaQuery.sizeOf()
    if [[ "$line" =~ MediaQuery\.of\([[:space:]]*context[[:space:]]*\)\.(size|padding|viewInsets|orientation) ]]; then
      add_finding "$file" "$line_num" "HIGH" "P08" "MediaQuery.of(context) causes whole-tree rebuilds. Use MediaQuery.sizeOf(context)."
    fi

    # P05: Nested shrinkWrap: true
    if [[ "$line" =~ shrinkWrap:[[:space:]]*true ]]; then
      add_finding "$file" "$line_num" "HIGH" "P05" "shrinkWrap: true forces two-pass layout. Refactor into CustomScrollView with Slivers."
    fi

    # P04: Opacity widget
    if [[ "$line" =~ Opacity\([[:space:]]*opacity: ]]; then
      add_finding "$file" "$line_num" "MEDIUM" "P04" "Opacity widget creates an offscreen buffer. Use AnimatedOpacity or FadeTransition."
    fi
  done < "$file"

done < <(find "$TARGET_DIR" -type f -name "*.dart" 2>/dev/null || true)

# 2. Check Native GDPR / RODO Defaults
ANDROID_MANIFEST="$TARGET_DIR/android/app/src/main/AndroidManifest.xml"
if [[ -f "$ANDROID_MANIFEST" ]]; then
  if ! grep -qs 'android:name="firebase_analytics_collection_enabled"[[:space:]]*android:value="false"' "$ANDROID_MANIFEST"; then
    add_finding "$ANDROID_MANIFEST" "1" "CRITICAL" "GDPR-01" "Missing native AndroidManifest default: firebase_analytics_collection_enabled must be false."
  fi
  if ! grep -qs 'android:name="firebase_crashlytics_collection_enabled"[[:space:]]*android:value="false"' "$ANDROID_MANIFEST"; then
    add_finding "$ANDROID_MANIFEST" "1" "CRITICAL" "GDPR-02" "Missing native AndroidManifest default: firebase_crashlytics_collection_enabled must be false."
  fi
fi

IOS_PLIST="$TARGET_DIR/ios/Runner/Info.plist"
if [[ -f "$IOS_PLIST" ]]; then
  if ! grep -qs '<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>[[:space:]]*<false/>' "$IOS_PLIST"; then
    add_finding "$IOS_PLIST" "1" "CRITICAL" "GDPR-03" "Missing native Info.plist default: FIREBASE_ANALYTICS_COLLECTION_ENABLED must be <false/>."
  fi
  if ! grep -qs '<key>FirebaseCrashlyticsCollectionEnabled</key>[[:space:]]*<false/>' "$IOS_PLIST"; then
    add_finding "$IOS_PLIST" "1" "CRITICAL" "GDPR-04" "Missing native Info.plist default: FirebaseCrashlyticsCollectionEnabled must be <false/>."
  fi
fi

# 3. Output Findings
if [[ "$JSON_MODE" = true ]]; then
  echo "["
  first=true
  for f in "${FINDINGS[@]}"; do
    IFS="|" read -r sev trap_id rel_file line msg <<< "$f"
    [[ "$first" = false ]] && echo ","
    first=false
    printf '  {"severity":"%s","trapId":"%s","file":"%s","line":%d,"message":"%s"}' \
      "$sev" "$trap_id" "$rel_file" "$line" "$msg"
  done
  echo ""
  echo "]"
else
  echo "=================================================="
  echo " Flutter Ultimate Static Code Audit"
  echo " Target: $TARGET_DIR"
  echo "=================================================="

  if [ ${#FINDINGS[@]} -eq 0 ]; then
    echo -e "\n[PASS] No performance traps or privacy violations detected!"
    exit 0
  fi

  for f in "${FINDINGS[@]}"; do
    IFS="|" read -r sev trap_id rel_file line msg <<< "$f"
    echo "[$sev] $trap_id in $rel_file:$line"
    echo "       $msg"
  done

  echo "--------------------------------------------------"
  echo " Total findings: ${#FINDINGS[@]}"
  echo "--------------------------------------------------"
fi

has_critical=false
for f in "${FINDINGS[@]}"; do
  if [[ "$f" =~ ^(CRITICAL|HIGH) ]]; then
    has_critical=true
    break
  fi
done

if [[ "$STRICT_MODE" = true && ${#FINDINGS[@]} -gt 0 ]]; then
  exit 1
elif [[ "$has_critical" = true ]]; then
  exit 1
else
  exit 0
fi
