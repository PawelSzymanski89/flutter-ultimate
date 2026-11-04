#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Deterministic Static Code Audit (POSIX Bash)
# ==============================================================================
set -euo pipefail

TARGET_PATH="."
JSON_MODE=false
STRICT_MODE=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --strict) STRICT_MODE=true ;;
    -*) ;;
    *) TARGET_PATH="$arg" ;;
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
  [[ -z "$file" ]] && continue
  [[ "$file" =~ (\.dart_tool|build|\.git|\.g\.dart|\.freezed\.dart) ]] && continue

  mapfile -t lines < "$file"
  total_lines=${#lines[@]}
  file_content=$(cat "$file")
  in_build_or_paint=false

  for ((i=0; i<total_lines; i++)); do
    line="${lines[$i]}"
    line_num=$((i + 1))

    # Track build or paint methods
    if [[ "$line" =~ Widget[[:space:]]+build[[:space:]]*\(|void[[:space:]]+paint[[:space:]]*\( ]]; then
      in_build_or_paint=true
    fi

    # Helper function for suppression check
    is_suppressed() {
      local trap="$1"
      if (( i > 0 )); then
        local prev="${lines[$((i - 1))]}"
        if [[ "$prev" =~ //[[:space:]]*flutter-ultimate:ignore[[:space:]]+$trap ]]; then
          return 0
        fi
      fi
      return 1
    }

    # K01: Unprotected BuildContext across async gap
    if [[ "$line" =~ (^|[[:space:]])await[[:space:]]+ ]]; then
      next_chunk=""
      for ((j=i+1; j<i+7 && j<total_lines; j++)); do
        next_chunk+="${lines[$j]}"$'\n'
      done
      if [[ "$next_chunk" =~ (Navigator\.of|ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)[[:space:]]*\([[:space:]]*context ]] || \
         [[ "$next_chunk" =~ context\.(read|watch|select|push|pop|go) ]]; then
        if ! [[ "$next_chunk" =~ if[[:space:]]*\([[:space:]]*!?[[:space:]]*(context\.)?mounted ]] && \
           ! [[ "$next_chunk" =~ "return;" ]] && \
           ! [[ "$next_chunk" =~ "mounted?" ]]; then
          if ! is_suppressed "K01"; then
            add_finding "$file" "$line_num" "CRITICAL" "K01" "BuildContext used across async gap without 'if (!context.mounted) return;' guard."
          fi
        fi
      fi
    fi

    # P03: Helper _buildX() methods instead of dedicated StatelessWidget
    if [[ "$line" =~ ^[[:space:]]*Widget[[:space:]]+(_build[A-Za-z0-9_]+)[[:space:]]*\( ]]; then
      method_name="${BASH_REMATCH[1]}"
      if ! is_suppressed "P03"; then
        add_finding "$file" "$line_num" "MEDIUM" "P03" "Helper '$method_name()' creates rebuild overhead. Extract into a const StatelessWidget."
      fi
    fi

    # P04: Instantiating Paint/Path inside build or paint
    if [[ "$in_build_or_paint" = true ]] && [[ "$line" =~ (final|var|Paint|Path)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?(Paint|Path)[[:space:]]*\([[:space:]]*\) ]]; then
      type_name="${BASH_REMATCH[3]}"
      if ! is_suppressed "P04"; then
        add_finding "$file" "$line_num" "HIGH" "P04" "Allocating $type_name inside build/paint causes GC churn. Cache as static final or member variable."
      fi
    fi

    # P07: MediaQuery.of() instead of MediaQuery.sizeOf()
    if [[ "$line" =~ MediaQuery\.of\([[:space:]]*context[[:space:]]*\)\.(size|padding|viewInsets|orientation|devicePixelRatio) ]]; then
      method="${BASH_REMATCH[1]}"
      if ! is_suppressed "P07"; then
        add_finding "$file" "$line_num" "HIGH" "P07" "MediaQuery.of(context).$method causes whole-tree rebuilds. Use MediaQuery.${method}Of(context)."
      fi
    fi

    # P12: Eager Future/Stream instantiation inside build()
    if [[ "$line" =~ (future|stream):[[:space:]]*[A-Za-z0-9_]+\.[A-Za-z0-9_]+[[:space:]]*\( ]]; then
      if ! is_suppressed "P12"; then
        add_finding "$file" "$line_num" "CRITICAL" "P12" "Eager asynchronous call inside builder resets on every rebuild. Cache Future/Stream in initState."
      fi
    fi

    # P19: Nested shrinkWrap: true
    if [[ "$line" =~ shrinkWrap:[[:space:]]*true ]]; then
      if ! is_suppressed "P19"; then
        add_finding "$file" "$line_num" "HIGH" "P19" "shrinkWrap: true forces two-pass layout calculation. Refactor into CustomScrollView with Slivers."
      fi
    fi

    # P21: Quadratic Multi-Pass Layout with IntrinsicHeight / IntrinsicWidth
    if [[ "$line" =~ Intrinsic(Height|Width)[[:space:]]*\( ]]; then
      dimension="${BASH_REMATCH[1]}"
      if ! is_suppressed "P21"; then
        add_finding "$file" "$line_num" "HIGH" "P21" "Intrinsic$dimension forces speculative \$O(N^2) dry layout passes. Prefer bounded constraints."
      fi
    fi

    # P26: Opacity widget
    if [[ "$line" =~ Opacity[[:space:]]*\( ]]; then
      if ! is_suppressed "P26"; then
        add_finding "$file" "$line_num" "MEDIUM" "P26" "Opacity widget creates an offscreen render buffer. Use AnimatedOpacity or FadeTransition."
      fi
    fi

    # P27: ClipRRect
    if [[ "$line" =~ ClipRRect[[:space:]]*\( ]]; then
      if ! is_suppressed "P27"; then
        add_finding "$file" "$line_num" "LOW" "P27" "ClipRRect creates an extra saveLayer call. Prefer BoxDecoration(borderRadius: ...) where possible."
      fi
    fi

  done

  # W01, W03, W06, W14: Disposal pairing checks in State classes
  if [[ "$file_content" =~ class[[:space:]]+[A-Za-z0-9_]+[[:space:]]+extends[[:space:]]+State\< ]]; then
    controllers=(
      "TextEditingController"
      "AnimationController"
      "ScrollController"
      "TabController"
      "PageController"
      "FocusNode"
      "FocusScopeNode"
      "VideoPlayerController"
      "CameraController"
      "AppLifecycleListener"
    )

    for ctrl in "${controllers[@]}"; do
      while IFS= read -r match_line; do
        [[ -z "$match_line" ]] && continue
        line_idx=$(echo "$match_line" | cut -d: -f1)
        var_name=$(echo "$match_line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]*=.*//; s/.*[[:space:]]+//')
        if [[ -n "$var_name" ]]; then
          if ! grep -qE "\b$var_name\.dispose[[:space:]]*\(" "$file"; then
            add_finding "$file" "$line_idx" "CRITICAL" "W01" "Resource '$var_name' ($ctrl) is instantiated but never disposed via '$var_name.dispose()' in dispose()."
          fi
        fi
      done < <(grep -nE "(final|late final|var)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?$ctrl\b" "$file" || true)
    done

    # W14: StreamController .close()
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      line_idx=$(echo "$match_line" | cut -d: -f1)
      var_name=$(echo "$match_line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]*=.*//; s/.*[[:space:]]+//')
      if [[ -n "$var_name" ]]; then
        if ! grep -qE "\b$var_name\.close[[:space:]]*\(" "$file"; then
          add_finding "$file" "$line_idx" "CRITICAL" "W14" "Stream sink '$var_name' (StreamController) must be closed via '$var_name.close()' in dispose()."
        fi
      fi
    done < <(grep -nE "(final|late final|var)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?StreamController\b" "$file" || true)

    # W03: StreamSubscription .cancel()
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      line_idx=$(echo "$match_line" | cut -d: -f1)
      var_name=$(echo "$match_line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]*=.*//; s/.*[[:space:]]+//')
      if [[ -n "$var_name" ]]; then
        if ! grep -qE "\b$var_name(\?\.|\.)cancel[[:space:]]*\(" "$file"; then
          add_finding "$file" "$line_idx" "CRITICAL" "W03" "StreamSubscription '$var_name' is active but never cancelled via '$var_name.cancel()' in dispose()."
        fi
      fi
    done < <(grep -nE "([A-Za-z0-9_]+)[[:space:]]*=[^;]*\.listen[[:space:]]*\(" "$file" || true)

    # W06: Timer .cancel()
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      line_idx=$(echo "$match_line" | cut -d: -f1)
      var_name=$(echo "$match_line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]*=.*//; s/.*[[:space:]]+//')
      if [[ -n "$var_name" ]]; then
        if ! grep -qE "\b$var_name(\?\.|\.)cancel[[:space:]]*\(" "$file"; then
          add_finding "$file" "$line_idx" "CRITICAL" "W06" "Timer '$var_name' is running in event loop but never cancelled via '$var_name.cancel()' in dispose()."
        fi
      fi
    done < <(grep -nE "([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*Timer(\.periodic)?[[:space:]]*\(" "$file" || true)
  fi

done < <(find "$TARGET_DIR" -type f -name "*.dart" 2>/dev/null || true)

# 2. Check pubspec.yaml for Up-to-Date Linter Package
PUBSPEC_PATH="$TARGET_DIR/pubspec.yaml"
if [[ -f "$PUBSPEC_PATH" ]]; then
  if ! grep -Eqs '(flutter_lints|very_good_analysis)' "$PUBSPEC_PATH"; then
    add_finding "$PUBSPEC_PATH" "1" "CRITICAL" "LINT-01" "Missing linter package in dev_dependencies. Add 'flutter_lints: ^5.0.0'."
  elif grep -Eqs 'flutter_lints:[[:space:]]*[\^~]?[0-3]\.' "$PUBSPEC_PATH"; then
    add_finding "$PUBSPEC_PATH" "1" "HIGH" "LINT-02" "Outdated flutter_lints version (legacy 1.x-3.x). Upgrade to '^5.0.0' or '^4.0.0' for Dart 3 rules."
  fi
fi

# 3. Check Native GDPR / RODO Defaults
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

# 4. Output Findings
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
    echo -e "\n[PASS] No performance traps, memory leaks, or context violations found!"
    exit 0
  fi

  critical_cnt=0
  high_cnt=0
  medium_cnt=0
  low_cnt=0

  for f in "${FINDINGS[@]}"; do
    IFS="|" read -r sev trap_id rel_file line msg <<< "$f"
    case "$sev" in
      CRITICAL) critical_cnt=$((critical_cnt + 1)) ;;
      HIGH) high_cnt=$((high_cnt + 1)) ;;
      MEDIUM) medium_cnt=$((medium_cnt + 1)) ;;
      LOW) low_cnt=$((low_cnt + 1)) ;;
    esac
    echo "[$sev] $trap_id in $rel_file:$line"
    echo "       $msg"
  done

  echo "--------------------------------------------------"
  echo " Audit Summary: $critical_cnt Critical, $high_cnt High, $medium_cnt Medium, $low_cnt Low"
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
