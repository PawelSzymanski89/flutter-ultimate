#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Deterministic Static Code Audit
# Compatible with macOS (Bash 3.2+), Linux, and Windows (Git Bash).
# ==============================================================================
set -euo pipefail

usage() {
  echo "Usage: $0 [--target <dir>] [--json] [--strict]" >&2
  exit 2
}

TARGET_PATH="."
JSON_MODE=false
STRICT_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "Error: --target requires a directory argument" >&2
        usage
      fi
      TARGET_PATH="$2"
      shift 2
      ;;
    --json)
      JSON_MODE=true
      shift
      ;;
    --strict)
      STRICT_MODE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage
      ;;
    *)
      if [[ "$TARGET_PATH" == "." ]]; then
        TARGET_PATH="$1"
        shift
      else
        echo "Error: Unexpected positional argument '$1'" >&2
        usage
      fi
      ;;
  esac
done

if [[ ! -d "$TARGET_PATH" ]]; then
  echo "Error: Target directory '$TARGET_PATH' does not exist" >&2
  exit 2
fi

TARGET_DIR="$(cd "$TARGET_PATH" && pwd)"
FINDINGS=()

add_finding() {
  local file="$1"
  local line="$2"
  local severity="$3"
  local trap_id="$4"
  local message="$5"
  local rel_file="${file#"$TARGET_DIR"/}"
  local rec="$severity|$trap_id|$rel_file|$line|$message"
  local existing
  if (( ${#FINDINGS[@]} > 0 )); then
    for existing in "${FINDINGS[@]}"; do
      [[ "$existing" == "$rec" ]] && return 0
    done
  fi
  FINDINGS+=("$rec")
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

# --- Disposal helpers (used by the W01/W03/W06/W14 pass; globals set per State class) ---
# A variable is State-owned when it is initialised at field level or declared as a field.
state_owned() {
  local var="$1" at_field_level="$2"
  [[ "$at_field_level" = true ]] && return 0
  [[ "$field_decls" == *"|$var|"* ]] && return 0
  return 1
}
# Methods of the class in which "var.action(" occurs (space separated).
released_where() {
  printf '%s' "$release_index" | tr '|' '\n' | { grep -E "^$1:$2:" || true; } | cut -d: -f3 | sort -u | tr '\n' ' '
}
# A release is reachable when it sits in dispose() itself or in a method dispose() calls (one level).
reachable_from_dispose() {
  local m
  for m in "$@"; do
    [[ "$m" == "dispose" ]] && return 0
    [[ "$dispose_calls" == *"|$m|"* ]] && return 0
  done
  return 1
}
release_msg() { # var kind action where
  local list
  if [[ -n "${4// /}" ]]; then
    list=$(printf '%s' "$4" | sed -E 's/ +$//; s/ /(), /g')
    printf "Resource '%s' (%s) is created by this State; '%s.%s()' exists only in %s(), which dispose() never calls (static heuristic: verify ownership and cleanup path)." "$1" "$2" "$1" "$3" "$list"
  else
    printf "Resource '%s' (%s) is created by this State but '%s.%s()' was not found in dispose() or in any method dispose() calls (static heuristic: verify ownership and cleanup path)." "$1" "$2" "$1" "$3"
  fi
}

# 1. Scan Dart Files
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel_file="${file#"$TARGET_DIR"/}"
  if [[ "$rel_file" =~ (^|[\\/])(build|\.dart_tool|\.git)([\\/]|$) ]] || \
     [[ "$file" =~ \.(g|freezed)\.dart$ ]]; then
    continue
  fi

  lines=()
  while IFS= read -r l || [[ -n "$l" ]]; do
    lines+=("$l")
  done < "$file"
  total_lines=${#lines[@]}
  file_content=$(cat "$file")

  # Brace depth before/after every line (comment-only lines ignored); shared by K01 and the W pass
  depth_before=()
  depth_after=()
  cur_d=0
  for ((q=0; q<total_lines; q++)); do
    depth_before[q]=$cur_d
    if ! [[ "${lines[$q]}" =~ ^[[:space:]]*// ]]; then
      q_open="${lines[$q]//[^{]/}"
      q_close="${lines[$q]//[^\}]/}"
      cur_d=$((cur_d + ${#q_open} - ${#q_close}))
    fi
    depth_after[q]=$cur_d
  done

  in_build_or_paint=false
  brace_depth=0

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
      # Enclosing function body = nearest preceding block opener that is not control flow
      # and sits shallower than the await. The scan stops where that body closes, so a
      # guard placed before the await (or in a sibling block) never counts.
      await_depth=${depth_before[$i]}
      body_depth=-1
      for ((h=i; h>=0; h--)); do
        if (( depth_after[h] > depth_before[h] )) && (( depth_before[h] < await_depth )); then
          h_line="${lines[$h]}"
          if ! [[ "$h_line" =~ ^[[:space:]]*(if|else|for|while|do|switch|try|catch|finally|case|default|\})([^A-Za-z0-9_]|$) ]]; then
            body_depth=$((depth_before[h] + 1))
            break
          fi
        fi
      done
      (( body_depth < 0 )) && body_depth=0

      # Skip the rest of the awaited statement: a multi-line argument list holds
      # callbacks (dialog builders, onPressed) that run inside the call, not after it.
      scan_from=$((i + 1))
      p_open="${line//[^(]/}"
      p_close="${line//[^)]/}"
      paren=$(( ${#p_open} - ${#p_close} ))
      if (( paren > 0 )); then
        for ((j=i+1; j<total_lines; j++)); do
          p_open="${lines[$j]//[^(]/}"
          p_close="${lines[$j]//[^)]/}"
          paren=$(( paren + ${#p_open} - ${#p_close} ))
          if (( paren <= 0 )); then
            scan_from=$((j + 1))
            break
          fi
        done
      fi

      in_mounted_if=false
      mounted_if_depth=0
      pending_neg_mounted_guard=false
      pending_neg_depth=0
      guarded=false

      for ((j=scan_from; j<total_lines; j++)); do
        f_line="${lines[$j]}"
        f_line_num=$((j + 1))
        f_before=${depth_before[$j]}
        f_after=${depth_after[$j]}

        if (( f_before < body_depth )); then
          break
        fi
        if [[ "$f_line" =~ ^[[:space:]]*// ]]; then
          continue
        fi

        if [[ "$in_mounted_if" = true ]] && (( f_before < mounted_if_depth )); then
          in_mounted_if=false
        fi
        if [[ "$pending_neg_mounted_guard" = true ]] && (( f_before < pending_neg_depth )); then
          pending_neg_mounted_guard=false
        fi

        # Early-exit guard on one line: if (!mounted) return;  /  if (!context.mounted) { return; }
        if [[ "$f_line" =~ if[[:space:]]*\(.*![[:space:]]*(context\.)?mounted.*\)[[:space:]]*(\{[[:space:]]*)?(return|throw) ]]; then
          guarded=true
          break
        fi

        # Multi-line if (!mounted) { ... return; }
        if [[ "$f_line" =~ if[[:space:]]*\(.*![[:space:]]*(context\.)?mounted.*\)[[:space:]]*\{ ]] && (( f_after > f_before )); then
          pending_neg_mounted_guard=true
          pending_neg_depth=$f_after
        elif [[ "$pending_neg_mounted_guard" = true ]] && [[ "$f_line" =~ (^|[^A-Za-z0-9_])(return|throw)([^A-Za-z0-9_]|$) ]]; then
          guarded=true
          break
        fi

        # Positive guard: if (mounted) / if (x && context.mounted) on the same line, or as a block
        line_guarded=false
        if [[ "$f_line" =~ if[[:space:]]*\((.*[^A-Za-z0-9_.!])?(context\.)?mounted([^A-Za-z0-9_]|$) ]]; then
          line_guarded=true
          if (( f_after > f_before )); then
            in_mounted_if=true
            mounted_if_depth=$f_after
          fi
        fi

        danger_op=""
        if [[ "$f_line" =~ setState[[:space:]]*\( ]]; then
          danger_op="setState()"
        elif [[ "$f_line" =~ Navigator\.(push|pop|of|maybePop|pushNamed|pushReplacement|popUntil)[[:space:]]*\( ]]; then
          danger_op="Navigator"
        elif [[ "$f_line" =~ (showDialog|showModalBottomSheet|showBottomSheet|showMenu|showDatePicker|showTimePicker)(\<[^\>]*\>)?[[:space:]]*\( ]]; then
          danger_op="Dialog"
        elif [[ "$f_line" =~ (ScaffoldMessenger\.of|Theme\.of|MediaQuery\.of)[[:space:]]*\([[:space:]]*context ]]; then
          danger_op="Context theme/messenger lookup"
        elif [[ "$f_line" =~ context\.(read|watch|select|push|pop|go) ]]; then
          danger_op="context extension method"
        fi

        if [[ -n "$danger_op" && "$guarded" = false && "$in_mounted_if" = false && "$line_guarded" = false ]]; then
          if ! is_suppressed "$f_line_num" "K01"; then
            add_finding "$file" "$f_line_num" "CRITICAL" "K01" "BuildContext ($danger_op) used after an await in the same function with no mounted guard in between (static heuristic: scans this function body only)."
          fi
          break
        fi

        if (( f_after < body_depth )); then
          break
        fi
      done
    fi

    # P03: Helper _buildX() methods instead of dedicated StatelessWidget
    if [[ "$line" =~ ^[[:space:]]*Widget[[:space:]]+(_build[A-Za-z0-9_]+)[[:space:]]*\( ]]; then
      method_name="${BASH_REMATCH[1]}"
      if ! is_suppressed "$line_num" "P03"; then
        add_finding "$file" "$line_num" "LOW" "P03" "Helper '$method_name()' rebuilds with parent. Consider extracting a const StatelessWidget for isolated rebuild boundaries."
      fi
    fi

    # P32: Instantiating Paint/Path inside build or paint
    if [[ "$in_build_or_paint" = true ]] && [[ "$line" =~ (final|var|Paint|Path)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(new[[:space:]]+)?(Paint|Path)[[:space:]]*\([[:space:]]*\) ]]; then
      type_name="${BASH_REMATCH[3]}"
      if ! is_suppressed "$line_num" "P32"; then
        add_finding "$file" "$line_num" "HIGH" "P32" "Allocating $type_name inside build/paint causes GC churn. Cache as static final or member variable."
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
    if [[ "$in_build_or_paint" = true ]] && [[ "$line" =~ (future|stream):[[:space:]]*[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*[[:space:]]*\( ]]; then
      if ! is_suppressed "$line_num" "P12"; then
        add_finding "$file" "$line_num" "HIGH" "P12" "Eager asynchronous call inside builder resets on every rebuild. Cache Future/Stream in initState or state holder."
      fi
    fi

    # P19: Potentially expensive shrinkWrap
    if [[ "$line" =~ (^|[^A-Za-z0-9_])shrinkWrap:[[:space:]]*true ]]; then
      if ! is_suppressed "$line_num" "P19"; then
        add_finding "$file" "$line_num" "HIGH" "P19" "shrinkWrap: true triggers expensive layout passes when nested in scrollables. Consider CustomScrollView with Slivers for unbounded lists."
      fi
    fi

    # P21: Quadratic Multi-Pass Layout with IntrinsicHeight / IntrinsicWidth
    if [[ "$line" =~ (^|[^A-Za-z0-9_])Intrinsic(Height|Width)[[:space:]]*\( ]]; then
      dimension="${BASH_REMATCH[2]}"
      if ! is_suppressed "$line_num" "P21"; then
        add_finding "$file" "$line_num" "HIGH" "P21" "Intrinsic$dimension forces speculative layout passes. Profile layout cost or use bounded layout constraints."
      fi
    fi

    # P26: Opacity widget (word boundary to avoid AnimatedOpacity or SliverOpacity; skip literal 0.0/1.0)
    if [[ "$line" =~ (^|[^A-Za-z0-9_])Opacity[[:space:]]*\( ]]; then
      is_noop_opacity=false
      re_zero_one='opacity:[[:space:]]*(0(\.0+)?|1(\.0+)?)[[:space:]]*(,|$|\))'
      re_closing_paren='\)[[:space:]]*[,;]?$'
      for ((k=i; k<i+6 && k<total_lines; k++)); do
        k_line="${lines[$k]}"
        if [[ "$k_line" =~ $re_zero_one ]]; then
          is_noop_opacity=true
          break
        fi
        if (( k > i )) && [[ "$k_line" =~ $re_closing_paren ]]; then
          break
        fi
      done

      if [[ "$is_noop_opacity" = false ]] && ! is_suppressed "$line_num" "P26"; then
        add_finding "$file" "$line_num" "MEDIUM" "P26" "Opacity widget may introduce an offscreen compositing pass. For simple items use color alpha; for animations use FadeTransition."
      fi
    fi

    # P27: ClipRRect
    if [[ "$line" =~ (^|[^A-Za-z0-9_])ClipRRect[[:space:]]*\( ]]; then
      if ! is_suppressed "$line_num" "P27"; then
        add_finding "$file" "$line_num" "LOW" "P27" "ClipRRect introduces clipping overhead. Prefer BoxDecoration(borderRadius: ...) where clipping child content is not required."
      fi
    fi

  done

  # W01, W03, W06, W14: Disposal pairing checks scoped to State classes & their dispose() methods
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

    for ((s=0; s<total_lines; s++)); do
      s_line="${lines[$s]}"
      if [[ "$s_line" =~ class[[:space:]]+([A-Za-z0-9_]+)[[:space:]]+extends[[:space:]]+State\< ]]; then
        state_class_start=$s
        state_class_end=$((total_lines - 1))
        class_base=${depth_before[$s]}
        for ((k=s+1; k<total_lines; k++)); do
          if (( depth_after[k] <= class_base )); then
            state_class_end=$k
            break
          fi
        done

        # Pass 1: field declarations, calls made from dispose(), and every release call with its enclosing method
        field_decls="|"
        dispose_calls="|"
        release_index="|"
        cur_method=""
        for ((m=state_class_start+1; m<=state_class_end; m++)); do
          m_line="${lines[$m]}"
          [[ "$m_line" =~ ^[[:space:]]*// ]] && continue
          if (( depth_before[m] == class_base + 1 )); then
            if [[ "$m_line" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\( ]]; then
              cur_method="${BASH_REMATCH[1]}"
            fi
            rest="$m_line"
            while [[ "$rest" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(=|\;)(.*)$ ]]; do
              field_decls+="${BASH_REMATCH[1]}|"
              rest="${BASH_REMATCH[3]}"
            done
          fi
          if [[ "$cur_method" == "dispose" ]]; then
            rest="$m_line"
            while [[ "$rest" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\((.*)$ ]]; do
              dispose_calls+="${BASH_REMATCH[1]}|"
              rest="${BASH_REMATCH[2]}"
            done
          fi
          rest="$m_line"
          while [[ "$rest" =~ ([A-Za-z_][A-Za-z0-9_]*)(\?\.|\.)(dispose|cancel|close)[[:space:]]*\((.*)$ ]]; do
            release_index+="${BASH_REMATCH[1]}:${BASH_REMATCH[3]}:$cur_method|"
            rest="${BASH_REMATCH[4]}"
          done
        done

        # Pass 2: resources created by this State (field initializer, or assignment to a declared field)
        for ((m=state_class_start+1; m<=state_class_end; m++)); do
          m_line="${lines[$m]}"
          m_line_num=$((m + 1))
          [[ "$m_line" =~ ^[[:space:]]*// ]] && continue
          at_field_level=false
          (( depth_before[m] == class_base + 1 )) && at_field_level=true

          # W01: Controllers
          for ctrl in "${controllers[@]}"; do
            if [[ "$m_line" =~ (^|[^A-Za-z0-9_])([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(new[[:space:]]+)?$ctrl($|[^A-Za-z0-9_]) ]]; then
              var_name="${BASH_REMATCH[2]}"
              if [[ -n "$var_name" && "$var_name" != "new" ]] && state_owned "$var_name" "$at_field_level"; then
                where=$(released_where "$var_name" dispose)
                # shellcheck disable=SC2086
                if ! reachable_from_dispose $where; then
                  if ! is_suppressed "$m_line_num" "W01"; then
                    add_finding "$file" "$m_line_num" "CRITICAL" "W01" "$(release_msg "$var_name" "$ctrl" dispose "$where")"
                  fi
                fi
              fi
            fi
          done

          # W14: StreamController
          if [[ "$m_line" =~ (^|[^A-Za-z0-9_])([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(new[[:space:]]+)?StreamController($|[^A-Za-z0-9_]) ]]; then
            var_name="${BASH_REMATCH[2]}"
            if [[ -n "$var_name" && "$var_name" != "new" ]] && state_owned "$var_name" "$at_field_level"; then
              where=$(released_where "$var_name" close)
              # shellcheck disable=SC2086
              if ! reachable_from_dispose $where; then
                if ! is_suppressed "$m_line_num" "W14"; then
                  add_finding "$file" "$m_line_num" "CRITICAL" "W14" "$(release_msg "$var_name" StreamController close "$where")"
                fi
              fi
            fi
          fi

          # W03: StreamSubscription
          re_listen='(^|[^A-Za-z0-9_])([A-Za-z0-9_]+)[[:space:]]*=[^;]*\.listen[[:space:]]*\('
          if [[ "$m_line" =~ $re_listen ]]; then
            var_name="${BASH_REMATCH[2]}"
            if [[ -n "$var_name" ]] && state_owned "$var_name" "$at_field_level"; then
              where=$(released_where "$var_name" cancel)
              # shellcheck disable=SC2086
              if ! reachable_from_dispose $where; then
                if ! is_suppressed "$m_line_num" "W03"; then
                  add_finding "$file" "$m_line_num" "CRITICAL" "W03" "$(release_msg "$var_name" StreamSubscription cancel "$where")"
                fi
              fi
            fi
          fi

          # W06: Timer
          if [[ "$m_line" =~ (^|[^A-Za-z0-9_])([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*Timer(\.periodic)?[[:space:]]*\( ]]; then
            var_name="${BASH_REMATCH[2]}"
            if [[ -n "$var_name" ]] && state_owned "$var_name" "$at_field_level"; then
              where=$(released_where "$var_name" cancel)
              # shellcheck disable=SC2086
              if ! reachable_from_dispose $where; then
                if ! is_suppressed "$m_line_num" "W06"; then
                  add_finding "$file" "$m_line_num" "CRITICAL" "W06" "$(release_msg "$var_name" Timer cancel "$where")"
                fi
              fi
            fi
          fi
        done
      fi
    done
  fi

done < <(find "$TARGET_DIR" -type f -name "*.dart" 2>/dev/null || true)

# 2. Check pubspec.yaml for Up-to-Date Linter Package
PUBSPEC_PATH="$TARGET_DIR/pubspec.yaml"
ANALYSIS_PATH="$TARGET_DIR/analysis_options.yaml"

has_linter=false
if [[ -f "$PUBSPEC_PATH" ]]; then
  if grep -Eqs '(flutter_lints|very_good_analysis|lints|solid_lints)' "$PUBSPEC_PATH"; then
    has_linter=true
  fi
fi
if [[ "$has_linter" = false && -f "$ANALYSIS_PATH" ]]; then
  if grep -Eqs '^[[:space:]]*include:[[:space:]]*' "$ANALYSIS_PATH"; then
    has_linter=true
  fi
fi

if [[ -f "$PUBSPEC_PATH" ]]; then
  if [[ "$has_linter" = false ]]; then
    add_finding "$PUBSPEC_PATH" "1" "MEDIUM" "LINT-01" "No standard linter package (flutter_lints, very_good_analysis, lints, solid_lints) or analysis_options.yaml include detected. Add a linter package to dev_dependencies."
  elif grep -Eqs 'flutter_lints:[[:space:]]*[\^~]?[0-3]\.' "$PUBSPEC_PATH"; then
    add_finding "$PUBSPEC_PATH" "1" "HIGH" "LINT-02" "Outdated flutter_lints version (legacy 1.x-3.x). Upgrade to a current release (e.g., ^5.0.0 or ^6.0.0) matching your Dart SDK."
  fi
fi

# 3. Check Native Privacy Manifest Flags (strictly conditioned on Firebase dependencies)
has_firebase_analytics=false
has_firebase_crashlytics=false
if [[ -f "$PUBSPEC_PATH" ]]; then
  if grep -Eqs '(^|[[:space:]])firebase_analytics:' "$PUBSPEC_PATH"; then
    has_firebase_analytics=true
  fi
  if grep -Eqs '(^|[[:space:]])firebase_crashlytics:' "$PUBSPEC_PATH"; then
    has_firebase_crashlytics=true
  fi
fi

ANDROID_MANIFEST="$TARGET_DIR/android/app/src/main/AndroidManifest.xml"
if [[ -f "$ANDROID_MANIFEST" ]]; then
  manifest_flat=$(tr '\r\n' ' ' < "$ANDROID_MANIFEST")
  if [[ "$has_firebase_analytics" = true ]]; then
    p1='android:name="firebase_analytics_collection_enabled"[[:space:]]*android:value="false"'
    if ! [[ "$manifest_flat" =~ $p1 ]]; then
      add_finding "$ANDROID_MANIFEST" "1" "CRITICAL" "GDPR-01" "Missing native AndroidManifest default: firebase_analytics_collection_enabled must be false."
    fi
  fi
  if [[ "$has_firebase_crashlytics" = true ]]; then
    p2='android:name="firebase_crashlytics_collection_enabled"[[:space:]]*android:value="false"'
    if ! [[ "$manifest_flat" =~ $p2 ]]; then
      add_finding "$ANDROID_MANIFEST" "1" "CRITICAL" "GDPR-02" "Missing native AndroidManifest default: firebase_crashlytics_collection_enabled must be false."
    fi
  fi
fi

IOS_PLIST="$TARGET_DIR/ios/Runner/Info.plist"
if [[ -f "$IOS_PLIST" ]]; then
  plist_flat=$(tr '\r\n' ' ' < "$IOS_PLIST")
  if [[ "$has_firebase_analytics" = true ]]; then
    p3='<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>[[:space:]]*<false/>'
    if ! [[ "$plist_flat" =~ $p3 ]]; then
      add_finding "$IOS_PLIST" "1" "CRITICAL" "GDPR-03" "Missing native Info.plist default: FIREBASE_ANALYTICS_COLLECTION_ENABLED must be <false/>."
    fi
  fi
  if [[ "$has_firebase_crashlytics" = true ]]; then
    p4='<key>FirebaseCrashlyticsCollectionEnabled</key>[[:space:]]*<false/>'
    if ! [[ "$plist_flat" =~ $p4 ]]; then
      add_finding "$IOS_PLIST" "1" "CRITICAL" "GDPR-04" "Missing native Info.plist default: FirebaseCrashlyticsCollectionEnabled must be <false/>."
    fi
  fi
fi

# 4. Output Findings
if [[ "$JSON_MODE" = true ]]; then
  if (( ${#FINDINGS[@]} == 0 )); then
    echo "[]"
    exit 0
  fi
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

  if (( ${#FINDINGS[@]} == 0 )); then
    printf '\n[PASS] No performance traps, memory leaks, or context violations found!\n'
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
if (( ${#FINDINGS[@]} > 0 )); then
  for f in "${FINDINGS[@]}"; do
    if [[ "$f" =~ ^(CRITICAL|HIGH) ]]; then
      has_critical=true
      break
    fi
  done
fi

if [[ "$STRICT_MODE" = true && ${#FINDINGS[@]} -gt 0 ]]; then
  exit 1
elif [[ "$has_critical" = true ]]; then
  exit 1
else
  exit 0
fi
