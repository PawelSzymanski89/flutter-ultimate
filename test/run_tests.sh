#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Test Suite Runner (POSIX / Bash 3.2+ compatible)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0

# ANSI Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

report_assert() {
  local name="$1"
  local condition="$2"
  local details="$3"

  if [[ "$condition" -eq 1 ]]; then
    printf '  %b[PASS]%b %s\n' "$GREEN" "$NC" "$name"
    PASSED=$((PASSED + 1))
  else
    printf '  %b[FAIL]%b %s\n' "$RED" "$NC" "$name"
    if [[ -n "$details" ]]; then
      printf '         %b%s%b\n' "$YELLOW" "$details" "$NC"
    fi
    FAILED=$((FAILED + 1))
  fi
}

echo "=================================================="
echo " Flutter Ultimate Test Suite (Bash 3.2+)"
echo " Project: $PROJECT_ROOT"
echo "=================================================="

# 1. Validate SKILL.md & Claude Code Plugin Architecture
printf '\n%b[1/6] Validating SKILL.md & Plugin Architecture...%b\n' "$CYAN" "$NC"
SKILL_PATH="$PROJECT_ROOT/SKILL.md"

if [[ ! -f "$SKILL_PATH" ]]; then
  report_assert "SKILL.md exists" 0 "File not found at $SKILL_PATH"
else
  report_assert "SKILL.md exists" 1 ""

  line_count=$(wc -l < "$SKILL_PATH" | tr -d ' ')
  if (( line_count < 500 )); then
    report_assert "SKILL.md line count < 500 lines" 1 ""
  else
    report_assert "SKILL.md line count < 500 lines" 0 "Current lines: $line_count"
  fi

  # Check line lengths <= 300 chars
  long_lines=0
  curr_line=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    curr_line=$((curr_line + 1))
    len=${#l}
    if (( len > 300 )); then
      long_lines=$((long_lines + 1))
    fi
  done < "$SKILL_PATH"

  if (( long_lines == 0 )); then
    report_assert "SKILL.md max line length <= 300 chars" 1 ""
  else
    report_assert "SKILL.md max line length <= 300 chars" 0 "$long_lines lines exceed 300 chars"
  fi

  if grep -q "^name:[[:space:]]*flutter-ultimate" "$SKILL_PATH"; then
    report_assert "SKILL.md has name: flutter-ultimate" 1 ""
  else
    report_assert "SKILL.md has name: flutter-ultimate" 0 "Missing name frontmatter"
  fi

  if grep -q "^description:[[:space:]]*" "$SKILL_PATH"; then
    report_assert "SKILL.md has description" 1 ""
  else
    report_assert "SKILL.md has description" 0 "Missing description frontmatter"
  fi

  # PowerShell removed from allowed-tools
  if grep -q "allowed-tools:.*PowerShell" "$SKILL_PATH"; then
    report_assert "allowed-tools does not contain PowerShell" 0 "PowerShell found in allowed-tools"
  else
    report_assert "allowed-tools does not contain PowerShell" 1 ""
  fi
fi

# Validate Plugin Packaging
PLUGIN_MANIFEST="$PROJECT_ROOT/.claude-plugin/plugin.json"
PLUGIN_SKILL="$PROJECT_ROOT/skills/flutter-ultimate/SKILL.md"
CMD_AUDIT="$PROJECT_ROOT/commands/flutter-audit.md"
CMD_REVIEW="$PROJECT_ROOT/commands/flutter-review.md"

if [[ -f "$PLUGIN_MANIFEST" ]]; then
  report_assert "plugin.json exists" 1 ""
else
  report_assert "plugin.json exists" 0 "Missing plugin.json"
fi

MARKETPLACE_MANIFEST="$PROJECT_ROOT/.claude-plugin/marketplace.json"
if [[ -f "$MARKETPLACE_MANIFEST" ]]; then
  report_assert "marketplace.json exists" 1 ""
else
  report_assert "marketplace.json exists" 0 "Missing marketplace.json"
fi

if [[ -f "$PLUGIN_SKILL" ]]; then
  report_assert "skills/flutter-ultimate/SKILL.md exists" 1 ""
  if cmp -s "$SKILL_PATH" "$PLUGIN_SKILL"; then
    report_assert "SKILL.md and skills/flutter-ultimate/SKILL.md are synchronized" 1 ""
  else
    report_assert "SKILL.md and skills/flutter-ultimate/SKILL.md are synchronized" 0 "Files differ"
  fi
else
  report_assert "skills/flutter-ultimate/SKILL.md exists" 0 "Missing skills/flutter-ultimate/SKILL.md"
fi

if [[ -f "$CMD_AUDIT" ]]; then
  report_assert "commands/flutter-audit.md exists" 1 ""
  if grep -q "^description:[[:space:]]*" "$CMD_AUDIT"; then
    report_assert "commands/flutter-audit.md has description" 1 ""
  else
    report_assert "commands/flutter-audit.md has description" 0 "Missing description frontmatter"
  fi
else
  report_assert "commands/flutter-audit.md exists" 0 "Missing commands/flutter-audit.md"
fi

if [[ -f "$CMD_REVIEW" ]]; then
  report_assert "commands/flutter-review.md exists" 1 ""
  if grep -q "^description:[[:space:]]*" "$CMD_REVIEW"; then
    report_assert "commands/flutter-review.md has description" 1 ""
  else
    report_assert "commands/flutter-review.md has description" 0 "Missing description frontmatter"
  fi
else
  report_assert "commands/flutter-review.md exists" 0 "Missing commands/flutter-review.md"
fi

# Validate and test activate.js hook
HOOK_ACTIVATE="$PROJECT_ROOT/hooks/activate.js"
if [[ -f "$HOOK_ACTIVATE" ]]; then
  report_assert "hooks/activate.js exists" 1 ""

  act_non_flutter=$(node "$HOOK_ACTIVATE" 2>&1 || true)
  if echo "$act_non_flutter" | grep -q "/flutter-ultimate:flutter-review"; then
    report_assert "activate.js in non-Flutter directory reports namespaced commands" 1 ""
  else
    report_assert "activate.js in non-Flutter directory reports namespaced commands" 0 "Output: $act_non_flutter"
  fi

  act_flutter=$(cd "$PROJECT_ROOT/test/fixtures/positive" && node "$HOOK_ACTIVATE" 2>&1 || true)
  if echo "$act_flutter" | grep -q "FLUTTER ULTIMATE MODE ACTIVE"; then
    report_assert "activate.js in Flutter workspace activates full mode" 1 ""
  else
    report_assert "activate.js in Flutter workspace activates full mode" 0 "Output: $act_flutter"
  fi
else
  report_assert "hooks/activate.js exists" 0 "Missing hooks/activate.js"
fi

# 2. Test CLI Contract & Error Handling
printf '\n%b[2/6] Testing CLI Contract & Error Handling...%b\n' "$CYAN" "$NC"
AUDIT_SH="$PROJECT_ROOT/scripts/audit-flutter.sh"

set +e
unk_out=$("$AUDIT_SH" --unknown-option 2>&1)
unk_exit=$?
mis_out=$("$AUDIT_SH" --target 2>&1)
mis_exit=$?
non_out=$("$AUDIT_SH" --target "$PROJECT_ROOT/non_existent_directory" 2>&1)
non_exit=$?
set -e

report_assert "Unknown CLI option exits with code 2" $(( unk_exit == 2 ? 1 : 0 )) "$unk_out"
report_assert "Missing --target argument exits with code 2" $(( mis_exit == 2 ? 1 : 0 )) "$mis_out"
report_assert "Non-existent target directory exits with code 2" $(( non_exit == 2 ? 1 : 0 )) "$non_out"

# 3. Test audit-flutter.sh on Positive Fixture
printf '\n%b[3/6] Testing audit-flutter.sh Positive Fixture...%b\n' "$CYAN" "$NC"
POS_DIR="$PROJECT_ROOT/test/fixtures/positive"

set +e
pos_output=$("$AUDIT_SH" --target "$POS_DIR" --json 2>&1)
pos_exit=$?
set -e

if (( pos_exit == 1 )); then
  report_assert "Positive fixture returns exit code 1" 1 ""
else
  report_assert "Positive fixture returns exit code 1" 0 "Actual exit: $pos_exit"
fi

expected_traps=(
  "P03" "P04" "P07" "P12" "P19" "P21" "P26" "P27"
  "K01" "W01" "W03" "W06" "W14"
  "LINT-02" "GDPR-01" "GDPR-02" "GDPR-03" "GDPR-04"
)

for trap_id in "${expected_traps[@]}"; do
  if echo "$pos_output" | grep -q "\"trapId\":\"$trap_id\""; then
    report_assert "Positive fixture detects $trap_id" 1 ""
  else
    report_assert "Positive fixture detects $trap_id" 0 "Trap $trap_id not found in audit JSON"
  fi
done

# 4. Test Single-Finding Contract & Strict Mode
printf '\n%b[4/6] Testing Single-Finding JSON Array Contract & Strict Mode...%b\n' "$CYAN" "$NC"
SINGLE_DIR="$PROJECT_ROOT/test/fixtures/single"

set +e
single_output=$("$AUDIT_SH" --target "$SINGLE_DIR" --json 2>&1)
single_exit=$?
single_strict_output=$("$AUDIT_SH" --target "$SINGLE_DIR" --json --strict 2>&1)
single_strict_exit=$?
set -e

report_assert "Single finding (MEDIUM) without --strict exits with code 0" $(( single_exit == 0 ? 1 : 0 )) "Exit: $single_exit"
report_assert "Single finding with --strict exits with code 1" $(( single_strict_exit == 1 ? 1 : 0 )) "$single_strict_output"

# Validate that single finding outputs a valid JSON array enclosing an object
is_json_array=0
case "$single_output" in
  \[*\{\"*\"*\}*\]) is_json_array=1 ;;
  *) is_json_array=0 ;;
esac
report_assert "Single finding outputs valid JSON array [{...}]" "$is_json_array" "Output: $single_output"

# 5. Test Negative & Suppression Fixtures
printf '\n%b[5/6] Testing Negative & Suppression Fixtures...%b\n' "$CYAN" "$NC"
NEG_DIR="$PROJECT_ROOT/test/fixtures/negative"

set +e
neg_output=$("$AUDIT_SH" --target "$NEG_DIR" --json 2>&1)
neg_exit=$?
set -e

report_assert "Negative fixture returns exit code 0" $(( neg_exit == 0 ? 1 : 0 )) "Actual exit: $neg_exit"
is_strict_empty=0
[[ "$neg_output" == "[]" ]] && is_strict_empty=1
report_assert "Negative fixture returns strict '[]' (not empty stdout)" "$is_strict_empty" "Output: $neg_output"

SUP_DIR="$PROJECT_ROOT/test/fixtures/suppression"
set +e
sup_output=$("$AUDIT_SH" --target "$SUP_DIR" --json 2>&1)
sup_exit=$?
set -e

report_assert "Suppression fixture returns exit code 0" $(( sup_exit == 0 ? 1 : 0 )) "Actual exit: $sup_exit"
is_sup_empty=0
[[ "$sup_output" == "[]" ]] && is_sup_empty=1
report_assert "Suppression fixture returns strict '[]' (not empty stdout)" "$is_sup_empty" "Output: $sup_output"

# 6. Test Bash <-> PowerShell Cross-Platform Parity
printf '\n%b[6/6] Testing Bash <-> PowerShell Cross-Platform Parity...%b\n' "$CYAN" "$NC"
PWSH_CMD=""
if command -v pwsh >/dev/null 2>&1; then
  PWSH_CMD="pwsh"
elif command -v powershell.exe >/dev/null 2>&1; then
  PWSH_CMD="powershell.exe"
fi

if [[ -n "$PWSH_CMD" ]]; then
  AUDIT_PS1="$PROJECT_ROOT/scripts/audit-flutter.ps1"
  set +e
  ps_pos=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Json 2>&1)
  ps_neg=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$NEG_DIR" -Json 2>&1)
  ps_sup=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$SUP_DIR" -Json 2>&1)
  ps_single=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$SINGLE_DIR" -Json 2>&1)
  set -e

  diff_pos=$(node -e '
    function norm(raw) {
      const arr = typeof raw === "string" ? JSON.parse(raw) : raw;
      return (arr || []).map(r => ({
        severity: String(r.severity || "").trim(),
        trapId: String(r.trapId || "").trim(),
        file: String(r.file || "").replace(/\\/g, "/").trim(),
        line: Number(r.line),
        message: String(r.message || "").trim()
      })).sort((a,b) => {
        return a.trapId.localeCompare(b.trapId) ||
               a.file.localeCompare(b.file) ||
               (a.line - b.line) ||
               a.severity.localeCompare(b.severity) ||
               a.message.localeCompare(b.message);
      });
    }
    const bash = norm(process.argv[1]);
    const ps = norm(process.argv[2]);
    if (bash.length !== ps.length) {
      console.error(`Count mismatch: Bash ${bash.length} vs PS ${ps.length}`);
      process.exit(1);
    }
    for (let i = 0; i < bash.length; i++) {
      const b = bash[i], p = ps[i];
      if (b.severity !== p.severity || b.trapId !== p.trapId || b.file !== p.file || b.line !== p.line || b.message !== p.message) {
        console.error(`Mismatch at [${i}]:\n  Bash: ${JSON.stringify(b)}\n  PS:   ${JSON.stringify(p)}`);
        process.exit(1);
      }
    }
  ' "$pos_output" "$ps_pos" 2>&1)
  diff_pos_exit=$?

  report_assert "Positive fixture parity: 18 findings with zero discrepancies in (severity, trapId, file, line, message)" $(( diff_pos_exit == 0 ? 1 : 0 )) "$diff_pos"

  diff_neg=$(node -e '
    const b = (process.argv[1] || "").trim();
    const p = (process.argv[2] || "").trim();
    if (b !== "[]" || p !== "[]") {
      console.error(`Negative mismatch: Bash "${b}" vs PS "${p}"`);
      process.exit(1);
    }
  ' "$neg_output" "$ps_neg" 2>&1)
  report_assert "Negative fixture parity: both return strict '[]'" $(( $? == 0 ? 1 : 0 )) "$diff_neg"

  diff_sup=$(node -e '
    const b = (process.argv[1] || "").trim();
    const p = (process.argv[2] || "").trim();
    if (b !== "[]" || p !== "[]") {
      console.error(`Suppression mismatch: Bash "${b}" vs PS "${p}"`);
      process.exit(1);
    }
  ' "$sup_output" "$ps_sup" 2>&1)
  report_assert "Suppression fixture parity: both return strict '[]'" $(( $? == 0 ? 1 : 0 )) "$diff_sup"

  diff_single=$(node -e '
    function norm(raw) {
      const arr = typeof raw === "string" ? JSON.parse(raw) : raw;
      return (arr || []).map(r => ({
        severity: String(r.severity || "").trim(),
        trapId: String(r.trapId || "").trim(),
        file: String(r.file || "").replace(/\\/g, "/").trim(),
        line: Number(r.line),
        message: String(r.message || "").trim()
      }));
    }
    const b = norm(process.argv[1]);
    const p = norm(process.argv[2]);
    if (b.length !== 1 || p.length !== 1 || JSON.stringify(b[0]) !== JSON.stringify(p[0])) {
      console.error(`Single mismatch: Bash ${JSON.stringify(b)} vs PS ${JSON.stringify(p)}`);
      process.exit(1);
    }
  ' "$single_output" "$ps_single" 2>&1)
  report_assert "Single finding fixture parity: exactly 1 matching record" $(( $? == 0 ? 1 : 0 )) "$diff_single"
else
  printf '  %b[SKIP]%b PowerShell not found; skipping cross-platform parity assertion\n' "$YELLOW" "$NC"
fi

# Summary
echo "=================================================="
if (( FAILED == 0 )); then
  printf '%b Test Summary: %d Passed, %d Failed%b\n' "$GREEN" "$PASSED" "$FAILED" "$NC"
  echo "=================================================="
  exit 0
else
  printf '%b Test Summary: %d Passed, %d Failed%b\n' "$RED" "$PASSED" "$FAILED" "$NC"
  echo "=================================================="
  exit 1
fi
