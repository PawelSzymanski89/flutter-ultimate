#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Test Suite Runner (POSIX / Bash 3.2+ compatible)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Windows caps a command line at 32767 chars, so scanner output reaches node as a file path
as_file() {
  printf '%s' "$2" > "$TMP_DIR/$1"
  printf '%s' "$TMP_DIR/$1"
}

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
    l="${l%$'\r'}"   # Git Bash on Windows may check out CRLF; do not count the carriage return
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

# Every references/<name>.md cited by the skill, the session mode and the commands exists at the repository root
missing_refs=""
while IFS= read -r ref; do
  [[ -f "$PROJECT_ROOT/$ref" ]] || missing_refs+="$ref "
done < <(cat "$SKILL_PATH" "$PROJECT_ROOT/hooks/mode.md" "$PROJECT_ROOT"/commands/*.md | grep -oE 'references/[A-Za-z0-9_.-]+\.md' | sort -u)
report_assert "Every references/*.md cited in SKILL.md, hooks/mode.md and commands/*.md exists" $(( ${#missing_refs} == 0 ? 1 : 0 )) "Missing: $missing_refs"

# Validate Plugin Packaging
PLUGIN_MANIFEST="$PROJECT_ROOT/.claude-plugin/plugin.json"
PLUGIN_SKILL="$PROJECT_ROOT/skills/flutter-ultimate/SKILL.md"
CMD_AUDIT="$PROJECT_ROOT/commands/audit.md"
CMD_REVIEW="$PROJECT_ROOT/commands/review.md"

if [[ -f "$PLUGIN_MANIFEST" ]]; then
  report_assert "plugin.json exists" 1 ""
else
  report_assert "plugin.json exists" 0 "Missing plugin.json"
fi

set +e
sh_version=$(sed -nE 's/^SCRIPT_VERSION="([^"]+)"$/\1/p' "$PROJECT_ROOT/scripts/audit-flutter.sh")
# shellcheck disable=SC2016
ps_version=$(sed -nE 's/^\$ScriptVersion = "([^"]+)".*$/\1/p' "$PROJECT_ROOT/scripts/audit-flutter.ps1")
# shellcheck disable=SC2016
version_check=$(node -e '
  const [plugin, market, sh, ps] = process.argv.slice(1);
  const p = require(plugin).version, m = require(market);
  const all = [p, m.metadata.version, ...m.plugins.map(x => x.version), sh, ps];
  if (all.some(v => v !== p)) { console.error("plugin.json, marketplace.json, audit-flutter.sh, audit-flutter.ps1: " + all.join(" ")); process.exit(1); }
' "$PLUGIN_MANIFEST" "$PROJECT_ROOT/.claude-plugin/marketplace.json" "$sh_version" "$ps_version" 2>&1)
version_exit=$?
set -e
report_assert "Version in plugin.json equals marketplace.json and both scanners" $(( version_exit == 0 ? 1 : 0 )) "$version_check"

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
  report_assert "commands/audit.md exists" 1 ""
  if grep -q "^description:[[:space:]]*" "$CMD_AUDIT"; then
    report_assert "commands/audit.md has description" 1 ""
  else
    report_assert "commands/audit.md has description" 0 "Missing description frontmatter"
  fi
else
  report_assert "commands/audit.md exists" 0 "Missing commands/audit.md"
fi

if [[ -f "$CMD_REVIEW" ]]; then
  report_assert "commands/review.md exists" 1 ""
  if grep -q "^description:[[:space:]]*" "$CMD_REVIEW"; then
    report_assert "commands/review.md has description" 1 ""
  else
    report_assert "commands/review.md has description" 0 "Missing description frontmatter"
  fi
else
  report_assert "commands/review.md exists" 0 "Missing commands/review.md"
fi

# Validate and test activate.js hook
HOOK_ACTIVATE="$PROJECT_ROOT/hooks/activate.js"
if [[ -f "$HOOK_ACTIVATE" ]]; then
  report_assert "hooks/activate.js exists" 1 ""

  act_non_flutter=$(cd "$PROJECT_ROOT" && { node "$HOOK_ACTIVATE" 2>&1 || true; })
  if [[ -z "$act_non_flutter" ]]; then
    report_assert "activate.js in non-Flutter directory prints nothing" 1 ""
  else
    report_assert "activate.js in non-Flutter directory prints nothing" 0 "Output: $act_non_flutter"
  fi

  act_flutter=$(cd "$PROJECT_ROOT/test/fixtures/positive" && { node "$HOOK_ACTIVATE" 2>&1 || true; })
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

set +e
help_out=$("$AUDIT_SH" --help 2>/dev/null)
help_exit=$?
help_err=$("$AUDIT_SH" --help 2>&1 >/dev/null)
set -e
report_assert "--help exits with code 0 and prints usage on stdout" $(( help_exit == 0 && ${#help_out} > 0 && ${#help_err} == 0 ? 1 : 0 )) "exit=$help_exit stdout=${#help_out} stderr=${#help_err}"

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
  "P03" "P32" "P07" "P12" "P19" "P21" "P26" "P27"
  "K01" "W01" "W03" "W05" "W06" "W14" "W21"
  "LINT-02" "GDPR-01" "GDPR-02" "GDPR-03" "GDPR-04"
)

for trap_id in "${expected_traps[@]}"; do
  if echo "$pos_output" | grep -q "\"trapId\":\"$trap_id\""; then
    report_assert "Positive fixture detects $trap_id" 1 ""
  else
    report_assert "Positive fixture detects $trap_id" 0 "Trap $trap_id not found in audit JSON"
  fi
done

# Full records (severity, trapId, file, line, message) must equal test/fixtures/positive/expected.json
EXPECTED_JSON="$POS_DIR/expected.json"
# shellcheck disable=SC2016
NORM_JS='
  const fs = require("fs");
  const norm = raw => JSON.parse(raw).map(r => JSON.stringify([String(r.severity), String(r.trapId), String(r.file).replace(/\\/g, "/"), Number(r.line), String(r.message)])).sort();
'
# shellcheck disable=SC2016
EXPECTED_COUNT=$(node -e "$NORM_JS"' console.log(norm(fs.readFileSync(process.argv[1], "utf8")).length);' "$EXPECTED_JSON")
set +e
# shellcheck disable=SC2016
expected_check=$(node -e "$NORM_JS"'
  const exp = norm(fs.readFileSync(process.argv[1], "utf8")), got = norm(fs.readFileSync(process.argv[2], "utf8"));
  const missing = exp.filter(x => !got.includes(x)), extra = got.filter(x => !exp.includes(x));
  if (exp.length !== got.length || missing.length || extra.length) { console.error("expected " + exp.length + ", got " + got.length + "\nmissing: " + missing.join("\n") + "\nextra: " + extra.join("\n")); process.exit(1); }
' "$EXPECTED_JSON" "$(as_file pos.json "$pos_output")" 2>&1)
expected_exit=$?
set -e
report_assert "Positive fixture: $EXPECTED_COUNT findings equal to expected.json (severity, trapId, file, line, message)" $(( expected_exit == 0 ? 1 : 0 )) "$expected_check"

# Dart files are scanned in ordinal order of the path relative to --target, whatever order the file system lists them in.
# lib/Zeta.dart sorts before lib/alpha.dart only by code point; a case-insensitive or locale order reverses them.
set +e
# shellcheck disable=SC2016
order_check=$(node -e '
  const files = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).map(r => String(r.file).replace(/\\/g, "/")).filter(f => f.endsWith(".dart"));
  const seq = files.filter((f, i) => i === 0 || f !== files[i - 1]);
  const ordinal = [...new Set(seq)].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  if (!seq.includes("lib/Zeta.dart") || !seq.includes("lib/alpha.dart") || JSON.stringify(seq) !== JSON.stringify(ordinal)) { console.error("file order: " + seq.join(" ")); process.exit(1); }
' "$TMP_DIR/pos.json" 2>&1)
order_exit=$?
set -e
report_assert "Positive fixture: Dart files appear in ordinal path order (lib/Zeta.dart before lib/alpha.dart)" $(( order_exit == 0 ? 1 : 0 )) "$order_check"

# --disable: listed rules leave every output and the exit code; unknown IDs are a CLI error
set +e
dis_output=$("$AUDIT_SH" --target "$POS_DIR" --json --disable GDPR-01,GDPR-02,GDPR-03,GDPR-04 2>&1)
"$AUDIT_SH" --target "$POS_DIR" --json --disable P03,NOPE >/dev/null 2>&1
dis_unknown_exit=$?
set -e
dis_gdpr=$(printf '%s' "$dis_output" | grep -c '"trapId":"GDPR-' || true)
dis_count=$(printf '%s' "$dis_output" | grep -c '"trapId"' || true)
report_assert "--disable GDPR-01,GDPR-02,GDPR-03,GDPR-04 removes every GDPR-* finding and nothing else" $(( dis_gdpr == 0 && dis_count == EXPECTED_COUNT - 4 ? 1 : 0 )) "GDPR: $dis_gdpr, total: $dis_count"
report_assert "--disable with an unknown rule ID exits with code 2" $(( dis_unknown_exit == 2 ? 1 : 0 )) "exit=$dis_unknown_exit"

# --respect-ignore drops exactly the K01 records under "// ignore[_for_file]: use_build_context_synchronously";
# --exclude drops exactly the records of the matched file. Both compared with expected.json record by record.
# shellcheck disable=SC2016
FLAG_JS="$NORM_JS"'
  const exp = norm(fs.readFileSync(process.argv[1], "utf8")), got = norm(fs.readFileSync(process.argv[2], "utf8"));
  const gone = JSON.parse(process.argv[3]);
  const want = exp.filter(x => !gone.some(g => x.includes(g)));
  if (want.length !== exp.length - Number(process.argv[4]) || JSON.stringify(want) !== JSON.stringify(got)) { console.error("want " + want.length + ", got " + got.length + "\n" + got.filter(x => !want.includes(x)).join("\n")); process.exit(1); }
'
set +e
ri_output=$("$AUDIT_SH" --target "$POS_DIR" --json --respect-ignore 2>&1)
ri_check=$(node -e "$FLAG_JS" "$EXPECTED_JSON" "$(as_file ri.json "$ri_output")" '["\"K01\",\"lib/lint_ignore_file.dart\",15,","\"K01\",\"lib/sample.dart\",339,","\"K01\",\"lib/sample.dart\",345,","\"K01\",\"lib/sample.dart\",350,","\"K01\",\"lib/sample.dart\",356,"]' 5 2>&1)
ri_exit=$?
ex_output=$("$AUDIT_SH" --target "$POS_DIR" --json --exclude '*sam?le.dart' 2>&1)
ex_check=$(node -e "$FLAG_JS" "$EXPECTED_JSON" "$(as_file ex.json "$ex_output")" '["\"lib/sample.dart\""]' "$(grep -c '"file":"lib/sample.dart"' "$EXPECTED_JSON")" 2>&1)
ex_exit=$?
"$AUDIT_SH" --target "$POS_DIR" --json --exclude '' >/dev/null 2>&1
ex_empty_exit=$?
"$AUDIT_SH" --target "$POS_DIR" --json --exclude 'lib/x.dart,' >/dev/null 2>&1
ex_trailing_exit=$?
set -e
report_assert "--respect-ignore removes the 5 K01 records under use_build_context_synchronously ignores (line above, list, line end, statement, file) and nothing else" $(( ri_exit == 0 ? 1 : 0 )) "$ri_check"
report_assert "--exclude '*sam?le.dart' removes every lib/sample.dart record and nothing else" $(( ex_exit == 0 ? 1 : 0 )) "$ex_check"
report_assert "--exclude with an empty pattern exits with code 2" $(( ex_empty_exit == 2 && ex_trailing_exit == 2 ? 1 : 0 )) "exit=$ex_empty_exit / $ex_trailing_exit"

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

set +e
"$AUDIT_SH" --target "$SINGLE_DIR" --json --fail-on HIGH >/dev/null 2>&1
failon_high_exit=$?
"$AUDIT_SH" --target "$SINGLE_DIR" --json --fail-on LOW >/dev/null 2>&1
failon_low_exit=$?
"$AUDIT_SH" --target "$SINGLE_DIR" --json --fail-on BOGUS >/dev/null 2>&1
failon_bad_exit=$?
set -e
report_assert "Single finding (MEDIUM) with --fail-on HIGH exits with code 0" $(( failon_high_exit == 0 ? 1 : 0 )) "exit=$failon_high_exit"
report_assert "Single finding (MEDIUM) with --fail-on LOW exits with code 1" $(( failon_low_exit == 1 ? 1 : 0 )) "exit=$failon_low_exit"
report_assert "--fail-on with an invalid value exits with code 2" $(( failon_bad_exit == 2 ? 1 : 0 )) "exit=$failon_bad_exit"

# Validate that single finding outputs a valid JSON array enclosing an object
is_json_array=0
case "$single_output" in
  \[*\{\"*\"*\}*\]) is_json_array=1 ;;
  *) is_json_array=0 ;;
esac
report_assert "Single finding outputs valid JSON array [{...}]" "$is_json_array" "Output: $single_output"

# 4b. SARIF output contract
printf '\n%b[4b/6] Testing SARIF output...%b\n' "$CYAN" "$NC"
PLUGIN_VERSION=$(node -e 'console.log(require(process.argv[1]).version)' "$PROJECT_ROOT/.claude-plugin/plugin.json")
set +e
sarif_pos=$("$AUDIT_SH" --target "$POS_DIR" --sarif 2>&1)
sarif_neg=$("$AUDIT_SH" --target "$PROJECT_ROOT/test/fixtures/negative" --sarif 2>&1)
"$AUDIT_SH" --target "$SINGLE_DIR" --json --sarif >/dev/null 2>&1
both_modes_exit=$?
# shellcheck disable=SC2016
sarif_check=$(node -e '
  const fs = require("fs");
  const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const run = d.runs[0];
  const results = run.results;
  const n = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).length;
  if (d.version !== "2.1.0") { console.error("version " + d.version); process.exit(1); }
  if (run.tool.driver.version !== process.argv[3]) { console.error("driver.version " + run.tool.driver.version + " != plugin.json " + process.argv[3]); process.exit(1); }
  if (results.length !== n) { console.error("results " + results.length + " != json findings " + n); process.exit(1); }
  const ids = new Set(run.tool.driver.rules.map(r => r.id));
  for (const r of results) {
    if (!ids.has(r.ruleId)) { console.error("rule missing for " + r.ruleId); process.exit(1); }
    if (!["error","warning","note"].includes(r.level)) { console.error("level " + r.level); process.exit(1); }
    const loc = r.locations[0].physicalLocation;
    if (!loc.artifactLocation.uri || loc.artifactLocation.uri.includes("\\") || !Number.isInteger(loc.region.startLine)) { console.error("location " + JSON.stringify(loc)); process.exit(1); }
  }
' "$(as_file sarif_pos.json "$sarif_pos")" "$TMP_DIR/pos.json" "$PLUGIN_VERSION" 2>&1)
sarif_check_exit=$?
set -e
report_assert "Positive fixture --sarif is SARIF 2.1.0 with one result per JSON finding, rules for every ruleId and driver.version == plugin.json" $(( sarif_check_exit == 0 ? 1 : 0 )) "$sarif_check"
set +e
# shellcheck disable=SC2016
sarif_neg_check=$(node -e 'const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (d.runs[0].results.length !== 0) { console.error("expected empty results"); process.exit(1); }' "$(as_file sarif_neg.json "$sarif_neg")" 2>&1)
sarif_neg_exit=$?
set -e
report_assert "Negative fixture --sarif is a valid document with empty results" $(( sarif_neg_exit == 0 ? 1 : 0 )) "$sarif_neg_check"
report_assert "--json --sarif together exit with code 2" $(( both_modes_exit == 2 ? 1 : 0 )) "exit=$both_modes_exit"

set +e
sarif_prefixed=$("$AUDIT_SH" --target "$POS_DIR" --sarif --uri-prefix './app//' 2>&1)
# shellcheck disable=SC2016
prefix_check=$(node -e '
  const uris = p => JSON.parse(require("fs").readFileSync(p, "utf8")).runs[0].results.map(r => r.locations[0].physicalLocation.artifactLocation.uri);
  const plain = uris(process.argv[1]), pre = uris(process.argv[2]);
  if (plain.length === 0 || plain.length !== pre.length || pre.some((u, i) => u !== "app/" + plain[i])) { console.error(pre.slice(0, 3).join(" ")); process.exit(1); }
' "$TMP_DIR/sarif_pos.json" "$(as_file sarif_prefixed.json "$sarif_prefixed")" 2>&1)
prefix_exit=$?
set -e
report_assert "--sarif --uri-prefix ./app// prefixes every artifactLocation.uri with app/" $(( prefix_exit == 0 ? 1 : 0 )) "$prefix_check"

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

  # shellcheck disable=SC2016
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
    const bash = norm(require("fs").readFileSync(process.argv[1], "utf8"));
    const ps = norm(require("fs").readFileSync(process.argv[2], "utf8"));
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
  ' "$TMP_DIR/pos.json" "$(as_file ps_pos.json "$ps_pos")" 2>&1)
  diff_pos_exit=$?

  report_assert "Positive fixture parity: $EXPECTED_COUNT findings with zero discrepancies in (severity, trapId, file, line, message)" $(( diff_pos_exit == 0 ? 1 : 0 )) "$diff_pos"

  # shellcheck disable=SC2016
  diff_neg=$(node -e '
    const fs = require("fs");
    const b = fs.readFileSync(process.argv[1], "utf8").trim();
    const p = fs.readFileSync(process.argv[2], "utf8").trim();
    if (b !== "[]" || p !== "[]") {
      console.error(`Negative mismatch: Bash "${b}" vs PS "${p}"`);
      process.exit(1);
    }
  ' "$(as_file neg.json "$neg_output")" "$(as_file ps_neg.json "$ps_neg")" 2>&1)
  report_assert "Negative fixture parity: both return strict '[]'" $(( $? == 0 ? 1 : 0 )) "$diff_neg"

  # shellcheck disable=SC2016
  diff_sup=$(node -e '
    const fs = require("fs");
    const b = fs.readFileSync(process.argv[1], "utf8").trim();
    const p = fs.readFileSync(process.argv[2], "utf8").trim();
    if (b !== "[]" || p !== "[]") {
      console.error(`Suppression mismatch: Bash "${b}" vs PS "${p}"`);
      process.exit(1);
    }
  ' "$(as_file sup.json "$sup_output")" "$(as_file ps_sup.json "$ps_sup")" 2>&1)
  report_assert "Suppression fixture parity: both return strict '[]'" $(( $? == 0 ? 1 : 0 )) "$diff_sup"

  # shellcheck disable=SC2016
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
    const b = norm(require("fs").readFileSync(process.argv[1], "utf8"));
    const p = norm(require("fs").readFileSync(process.argv[2], "utf8"));
    if (b.length !== 1 || p.length !== 1 || JSON.stringify(b[0]) !== JSON.stringify(p[0])) {
      console.error(`Single mismatch: Bash ${JSON.stringify(b)} vs PS ${JSON.stringify(p)}`);
      process.exit(1);
    }
  ' "$(as_file single.json "$single_output")" "$(as_file ps_single.json "$ps_single")" 2>&1)
  report_assert "Single finding fixture parity: exactly 1 matching record" $(( $? == 0 ? 1 : 0 )) "$diff_single"

  set +e
  ps_sarif=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Sarif 2>&1)
  # shellcheck disable=SC2016
  diff_sarif=$(node -e '
    const norm = p => { const d = JSON.parse(require("fs").readFileSync(p, "utf8")); d.runs[0].results.forEach(r => { r.locations[0].physicalLocation.artifactLocation.uri = r.locations[0].physicalLocation.artifactLocation.uri.replace(/\\/g, "/"); }); return JSON.stringify(d); };
    const b = norm(process.argv[1]), p = norm(process.argv[2]);
    if (b !== p) { console.error("SARIF differs:\n" + b.slice(0, 400) + "\n---\n" + p.slice(0, 400)); process.exit(1); }
  ' "$TMP_DIR/sarif_pos.json" "$(as_file ps_sarif.json "$ps_sarif")" 2>&1)
  diff_sarif_exit=$?
  set -e
  report_assert "Positive fixture SARIF parity: identical documents" $(( diff_sarif_exit == 0 ? 1 : 0 )) "$diff_sarif"

  set +e
  ps_sarif_prefixed=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Sarif -UriPrefix './app//' 2>&1)
  ps_dis=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Json -Disable GDPR-01,GDPR-02,GDPR-03,GDPR-04 2>&1)
  # shellcheck disable=SC2016
  diff_flags=$(node -e '
    const read = p => require("fs").readFileSync(p, "utf8");
    const doc = p => JSON.stringify(JSON.parse(read(p)));
    const recs = p => JSON.parse(read(p)).map(r => JSON.stringify([r.severity, r.trapId, String(r.file).replace(/\\/g, "/"), Number(r.line), r.message])).sort().join("\n");
    if (doc(process.argv[1]) !== doc(process.argv[2])) { console.error("--uri-prefix SARIF differs"); process.exit(1); }
    if (recs(process.argv[3]) !== recs(process.argv[4])) { console.error("--disable JSON differs"); process.exit(1); }
  ' "$TMP_DIR/sarif_prefixed.json" "$(as_file ps_sarif_prefixed.json "$ps_sarif_prefixed")" "$(as_file dis.json "$dis_output")" "$(as_file ps_dis.json "$ps_dis")" 2>&1)
  diff_flags_exit=$?
  set -e
  report_assert "--disable and --uri-prefix parity: identical JSON and SARIF" $(( diff_flags_exit == 0 ? 1 : 0 )) "$diff_flags"

  set +e
  ps_ri=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Json -RespectIgnore 2>&1)
  ps_ex=$("$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Json -Exclude '*sam?le.dart' 2>&1)
  "$PWSH_CMD" -NoProfile -ExecutionPolicy Bypass -File "$AUDIT_PS1" -Target "$POS_DIR" -Json -Exclude 'lib/x.dart,' >/dev/null 2>&1
  ps_ex_empty_exit=$?
  # shellcheck disable=SC2016
  diff_flags2=$(node -e '
    const recs = p => JSON.parse(require("fs").readFileSync(p, "utf8")).map(r => JSON.stringify([r.severity, r.trapId, String(r.file).replace(/\\/g, "/"), Number(r.line), r.message])).sort().join("\n");
    if (recs(process.argv[1]) !== recs(process.argv[2])) { console.error("--respect-ignore JSON differs"); process.exit(1); }
    if (recs(process.argv[3]) !== recs(process.argv[4])) { console.error("--exclude JSON differs"); process.exit(1); }
  ' "$TMP_DIR/ri.json" "$(as_file ps_ri.json "$ps_ri")" "$TMP_DIR/ex.json" "$(as_file ps_ex.json "$ps_ex")" 2>&1)
  diff_flags2_exit=$?
  set -e
  report_assert "--respect-ignore and --exclude parity: identical JSON; -Exclude with an empty pattern exits with code 2" $(( diff_flags2_exit == 0 && ps_ex_empty_exit == 2 ? 1 : 0 )) "$diff_flags2 exit=$ps_ex_empty_exit"
else
  if [[ "${FU_REQUIRE_PWSH:-}" == "1" ]]; then
    report_assert "PowerShell available for the parity assertions (FU_REQUIRE_PWSH=1)" 0 "Neither pwsh nor powershell.exe found on PATH"
  else
    printf '  %b[SKIP]%b PowerShell not found; skipping cross-platform parity assertion\n' "$YELLOW" "$NC"
  fi
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
