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
    printf "  ${GREEN}[PASS]${NC} %s\n" "$name"
    PASSED=$((PASSED + 1))
  else
    printf "  ${RED}[FAIL]${NC} %s\n" "$name"
    if [[ -n "$details" ]]; then
      printf "         ${YELLOW}%s${NC}\n" "$details"
    fi
    FAILED=$((FAILED + 1))
  fi
}

echo "=================================================="
echo " Flutter Ultimate Test Suite (Bash 3.2+)"
echo " Project: $PROJECT_ROOT"
echo "=================================================="

# 1. Validate SKILL.md Specification
printf "\n${CYAN}[1/4] Validating SKILL.md Specification...${NC}\n"
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
fi

# 2. Test audit-flutter.sh on Positive Fixture
printf "\n${CYAN}[2/4] Testing audit-flutter.sh Positive Fixture...${NC}\n"
POS_DIR="$PROJECT_ROOT/test/fixtures/positive"
AUDIT_SH="$PROJECT_ROOT/scripts/audit-flutter.sh"

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

# 3. Test audit-flutter.sh on Negative Fixture
printf "\n${CYAN}[3/4] Testing audit-flutter.sh Negative Fixture...${NC}\n"
NEG_DIR="$PROJECT_ROOT/test/fixtures/negative"

set +e
neg_output=$("$AUDIT_SH" --target "$NEG_DIR" --json 2>&1)
neg_exit=$?
set -e

if (( neg_exit == 0 )); then
  report_assert "Negative fixture returns exit code 0" 1 ""
else
  report_assert "Negative fixture returns exit code 0" 0 "Actual exit: $neg_exit"
fi

if [[ -z "$neg_output" ]] || [[ "$neg_output" =~ ^\[[[:space:]]*\]$ ]]; then
  report_assert "Negative fixture has 0 findings" 1 ""
else
  report_assert "Negative fixture has 0 findings" 0 "Unexpected findings detected: $neg_output"
fi

# 4. Test audit-flutter.sh on Suppression Fixture
printf "\n${CYAN}[4/4] Testing audit-flutter.sh Suppression Fixture...${NC}\n"
SUP_DIR="$PROJECT_ROOT/test/fixtures/suppression"

set +e
sup_output=$("$AUDIT_SH" --target "$SUP_DIR" --json 2>&1)
sup_exit=$?
set -e

if (( sup_exit == 0 )); then
  report_assert "Suppression fixture returns exit code 0" 1 ""
else
  report_assert "Suppression fixture returns exit code 0" 0 "Actual exit: $sup_exit"
fi

if [[ -z "$sup_output" ]] || [[ "$sup_output" =~ ^\[[[:space:]]*\]$ ]]; then
  report_assert "Suppression fixture has 0 findings" 1 ""
else
  report_assert "Suppression fixture has 0 findings" 0 "Unexpected findings detected: $sup_output"
fi

# Summary
echo "=================================================="
if (( FAILED == 0 )); then
  printf "${GREEN} Test Summary: %d Passed, %d Failed${NC}\n" "$PASSED" "$FAILED"
  echo "=================================================="
  exit 0
else
  printf "${RED} Test Summary: %d Passed, %d Failed${NC}\n" "$PASSED" "$FAILED"
  echo "=================================================="
  exit 1
fi
