#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Deterministic Static Code Audit
# Compatible with macOS (Bash 3.2+), Linux, and Windows (Git Bash).
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

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# 1. Scan Dart Files
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ "$file" =~ (\.dart_tool|build|\.git|\.g\.dart|\.freezed\.dart) ]] && continue

  lines=()
  while IFS= read -r l || [[ -n "$l" ]]; do
    lines+=("$l")
  done < "$file"
  total_lines=${#lines[@]}
  file_content=$(cat "$file")

  in_build_or_paint=false
  brace_depth=0

  is_suppressed() {
    local target_line="$1"
    local trap="$2"
    if (( target_line > 1 )); then
      local prev="${lines[$((target_line - 2))]}"
      if [[ "$prev" =~ //[[:space:]]*flutter-ultimate:ignore[[:space:]]+$trap ]]; then
        return 0
      fi
    fi
    return 1
  }

  for ((i=0; i<total_lines; i++)); do
    line="${lines[$i]}"
    line_num=$((i + 1))

    # Skip pure single-line comment lines for code analysis
    if [[ "$line" =~ ^[[:space:]]*// ]]; then
      continue
    fi

    # Track entry and exit of build or paint methods
    if [[ "$line" =~ Widget[[:space:]]+build[[:space:]]*\(|void[[:space:]]+paint[[:space:]]*\( ]]; then
      in_build_or_paint=true
      brace_depth=0
    fi

    if [[ "$in_build_or_paint" = true ]]; then
      open_chars="${line//[^{]/}"
      close_chars="${line//[^\}]/}"
      opens=${#open_chars}
      closes=${#close_chars}
      brace_depth=$((brace_depth + opens - closes))
      if (( brace_depth <= 0 )) && (( opens > 0 || closes > 0 )); then
        in_build_or_paint=false
      fi
    fi

    # K01: Unprotected BuildContext across async gap
    if [[ "$line" =~ (^|[[:space:]])await[[:space:]]+ ]]; then
      next_chunk=""
      for ((j=i+1; j<i+7 && j<total_lines; j++)); do
        next_chunk+="${lines[$j]}"$'\n'
      done
      if [[ "$next_chunk" =~ (Navigator\.of|ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)[[:space:]]*\([[:space:]]*context ]] || \
         [[ "$next_chunk" =~ context\.(read|watch|select|push|pop|go) ]]; then
        if ! [[ "$next_chunk" =~ if[[:space:]]*\([[:space:]]*!?[[:space:]]*(context\.)?mounted ]] && \
           ! [[ "$next_chunk" =~ mounted\? ]]; then
          if ! is_suppressed "$line_num" "K01"; then
            add_finding "$file" "$line_num" "CRITICAL" "K01" "BuildContext used across async gap without 'if (!context.mounted) return;' guard."
          fi
        fi
      fi
    fi

    # P03: Helper _buildX() methods instead of dedicated StatelessWidget
    if [[ "$line" =~ ^[[:space:]]*Widget[[:space:]]+(_build[A-Za-z0-9_]+)[[:space:]]*\( ]]; then
      method_name="${BASH_REMATCH[1]}"
      if ! is_suppressed "$line_num" "P03"; then
        add_finding "$file" "$line_num" "LOW" "P03" "Helper '$method_name()' rebuilds with parent. Consider extracting a const StatelessWidget for isolated rebuild boundaries."
      fi
    fi

    # P04: Instantiating Paint/Path inside build or paint
    if [[ "$in_build_or_paint" = true ]] && [[ "$line" =~ (final|var|Paint|Path)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?(Paint|Path)[[:space:]]*\([[:space:]]*\) ]]; then
      type_name="${BASH_REMATCH[3]}"
      if ! is_suppressed "$line_num" "P04"; then
        add_finding "$file" "$line_num" "HIGH" "P04" "Allocating $type_name inside build/paint causes GC churn. Cache as static final or member variable."
      fi
    fi

    # P07: MediaQuery.of() instead of MediaQuery.sizeOf()
    if [[ "$line" =~ MediaQuery\.of\([[:space:]]*context[[:space:]]*\)\.(size|padding|viewInsets|orientation|devicePixelRatio) ]]; then
      method="${BASH_REMATCH[1]}"
      if ! is_suppressed "$line_num" "P07"; then
        add_finding "$file" "$line_num" "HIGH" "P07" "MediaQuery.of(context).$method establishes broad dependency on MediaQueryData. Use MediaQuery.${method}Of(context) to narrow rebuild scope."
      fi
    fi

    # P12: Eager Future/Stream instantiation inside build()
    if [[ "$line" =~ (future|stream):[[:space:]]*[A-Za-z0-9_]+\.[A-Za-z0-9_]+[[:space:]]*\( ]]; then
      if ! is_suppressed "$line_num" "P12"; then
        add_finding "$file" "$line_num" "CRITICAL" "P12" "Eager asynchronous call inside builder resets on every rebuild. Cache Future/Stream in initState."
      fi
    fi

    # P19: Potentially expensive shrinkWrap
    if [[ "$line" =~ shrinkWrap:[[:space:]]*true ]]; then
      if ! is_suppressed "$line_num" "P19"; then
        add_finding "$file" "$line_num" "HIGH" "P19" "shrinkWrap: true triggers expensive layout passes when nested in scrollables. Consider CustomScrollView with Slivers for unbounded lists."
      fi
    fi

    # P21: Quadratic Multi-Pass Layout with IntrinsicHeight / IntrinsicWidth
    if [[ "$line" =~ Intrinsic(Height|Width)[[:space:]]*\( ]]; then
      dimension="${BASH_REMATCH[1]}"
      if ! is_suppressed "$line_num" "P21"; then
        add_finding "$file" "$line_num" "HIGH" "P21" "Intrinsic$dimension forces speculative layout passes. Profile layout cost or use bounded layout constraints."
      fi
    fi

    # P26: Opacity widget
    if [[ "$line" =~ Opacity[[:space:]]*\( ]]; then
      if ! is_suppressed "$line_num" "P26"; then
        add_finding "$file" "$line_num" "MEDIUM" "P26" "Opacity widget may introduce an offscreen compositing pass. For simple items use color alpha; for animations use FadeTransition."
      fi
    fi

    # P27: ClipRRect
    if [[ "$line" =~ ClipRRect[[:space:]]*\( ]]; then
      if ! is_suppressed "$line_num" "P27"; then
        add_finding "$file" "$line_num" "LOW" "P27" "ClipRRect introduces clipping overhead. Prefer BoxDecoration(borderRadius: ...) where clipping child content is not required."
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
            if ! is_suppressed "$line_idx" "W01"; then
              add_finding "$file" "$line_idx" "CRITICAL" "W01" "Resource '$var_name' ($ctrl) is instantiated in State but never disposed via '$var_name.dispose()' in dispose()."
            fi
          fi
        fi
      done < <(grep -nE "[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?$ctrl\b" "$file" || true)
    done

    # W14: StreamController .close()
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      line_idx=$(echo "$match_line" | cut -d: -f1)
      var_name=$(echo "$match_line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]*=.*//; s/.*[[:space:]]+//')
      if [[ -n "$var_name" ]]; then
        if ! grep -qE "\b$var_name\.close[[:space:]]*\(" "$file"; then
          if ! is_suppressed "$line_idx" "W14"; then
            add_finding "$file" "$line_idx" "CRITICAL" "W14" "Stream sink '$var_name' (StreamController) must be closed via '$var_name.close()' in dispose()."
          fi
        fi
      fi
    done < <(grep -nE "[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?StreamController\b" "$file" || true)

    # W03: StreamSubscription .cancel()
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      line_idx=$(echo "$match_line" | cut -d: -f1)
      var_name=$(echo "$match_line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]*=.*//; s/.*[[:space:]]+//')
      if [[ -n "$var_name" ]]; then
        if ! grep -qE "\b$var_name(\?\.|\.)cancel[[:space:]]*\(" "$file"; then
          if ! is_suppressed "$line_idx" "W03"; then
            add_finding "$file" "$line_idx" "CRITICAL" "W03" "StreamSubscription '$var_name' is active but never cancelled via '$var_name.cancel()' in dispose()."
          fi
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
          if ! is_suppressed "$line_idx" "W06"; then
            add_finding "$file" "$line_idx" "CRITICAL" "W06" "Timer '$var_name' is running in event loop but never cancelled via '$var_name.cancel()' in dispose()."
          fi
        fi
      fi
    done < <(grep -nE "([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*Timer(\.periodic)?[[:space:]]*\(" "$file" || true)
  fi

done < <(find "$TARGET_DIR" -type f -name "*.dart" 2>/dev/null || true)

# 2. Check pubspec.yaml for Up-to-Date Linter Package
PUBSPEC_PATH="$TARGET_DIR/pubspec.yaml"
if [[ -f "$PUBSPEC_PATH" ]]; then
  if ! grep -Eqs '(flutter_lints|very_good_analysis)' "$PUBSPEC_PATH"; then
    add_finding "$PUBSPEC_PATH" "1" "CRITICAL" "LINT-01" "Missing linter package in dev_dependencies. Add 'flutter_lints: ^5.0.0' or current package."
  elif grep -Eqs 'flutter_lints:[[:space:]]*[\^~]?[0-3]\.' "$PUBSPEC_PATH"; then
    add_finding "$PUBSPEC_PATH" "1" "HIGH" "LINT-02" "Outdated flutter_lints version (legacy 1.x-3.x). Upgrade to a current release (e.g., ^5.0.0 or ^6.0.0) matching your Dart SDK."
  fi
fi

# 3. Check Native Privacy Manifest Flags
ANDROID_MANIFEST="$TARGET_DIR/android/app/src/main/AndroidManifest.xml"
if [[ -f "$ANDROID_MANIFEST" ]]; then
  manifest_flat=$(tr '\r\n' ' ' < "$ANDROID_MANIFEST")
  p1='android:name="firebase_analytics_collection_enabled"[[:space:]]*android:value="false"'
  p2='android:name="firebase_crashlytics_collection_enabled"[[:space:]]*android:value="false"'
  if ! [[ "$manifest_flat" =~ $p1 ]]; then
    add_finding "$ANDROID_MANIFEST" "1" "CRITICAL" "GDPR-01" "Missing native AndroidManifest default: firebase_analytics_collection_enabled must be false."
  fi
  if ! [[ "$manifest_flat" =~ $p2 ]]; then
    add_finding "$ANDROID_MANIFEST" "1" "CRITICAL" "GDPR-02" "Missing native AndroidManifest default: firebase_crashlytics_collection_enabled must be false."
  fi
fi

IOS_PLIST="$TARGET_DIR/ios/Runner/Info.plist"
if [[ -f "$IOS_PLIST" ]]; then
  plist_flat=$(tr '\r\n' ' ' < "$IOS_PLIST")
  p3='<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>[[:space:]]*<false/>'
  p4='<key>FirebaseCrashlyticsCollectionEnabled</key>[[:space:]]*<false/>'
  if ! [[ "$plist_flat" =~ $p3 ]]; then
    add_finding "$IOS_PLIST" "1" "CRITICAL" "GDPR-03" "Missing native Info.plist default: FIREBASE_ANALYTICS_COLLECTION_ENABLED must be <false/>."
  fi
  if ! [[ "$plist_flat" =~ $p4 ]]; then
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
    esc_sev=$(json_escape "$sev")
    esc_trap=$(json_escape "$trap_id")
    esc_file=$(json_escape "$rel_file")
    esc_msg=$(json_escape "$msg")
    printf '  {"severity":"%s","trapId":"%s","file":"%s","line":%d,"message":"%s"}' \
      "$esc_sev" "$esc_trap" "$esc_file" "$line" "$esc_msg"
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
