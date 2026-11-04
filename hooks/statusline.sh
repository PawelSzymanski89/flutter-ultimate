#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Statusline Indicator
# Displays [PONYTAIL] (if active) + [FLUTTER] badge in the bottom status line:
# - Bright blue (\033[38;5;75m) when workspace is inside a Flutter project
# - Subtle gray (\033[38;5;245m) otherwise
# ==============================================================================
input=$(cat)

# 1. Chain Ponytail statusline if installed
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
pony=$(node -e '
  const fs = require("fs");
  const path = require("path");
  const base = path.join(process.argv[1] || "", "plugins/cache/ponytail/ponytail");
  if (!fs.existsSync(base)) process.exit(0);
  try {
    const dirs = fs.readdirSync(base).sort((a,b) => a.localeCompare(b, undefined, {numeric: true}));
    for (let i = dirs.length - 1; i >= 0; i--) {
      const p = path.join(base, dirs[i], "hooks/ponytail-statusline.sh");
      if (fs.existsSync(p)) { process.stdout.write(p); break; }
    }
  } catch(e) {}
' "$claude_dir" 2>/dev/null || true)

if [ -z "$pony" ] && [ -f "$claude_dir/ponytail-statusline.sh" ]; then
  pony="$claude_dir/ponytail-statusline.sh"
fi

if [ -n "$pony" ] && [ -f "$pony" ]; then
  pony_out=$(printf '%s' "$input" | bash "$pony" 2>/dev/null || true)
  if [ -n "$pony_out" ]; then
    printf '%s ' "$pony_out"
  fi
fi

# 2. Extract workspace directory from JSON payload
dir=$(printf '%s' "$input" | node -e '
  let d = "";
  try {
    const obj = JSON.parse(require("fs").readFileSync(0, "utf8"));
    d = (obj.workspace && obj.workspace.current_dir) || obj.cwd || "";
  } catch (e) {}
  process.stdout.write(d);
' 2>/dev/null || true)

[ -z "$dir" ] && dir="$PWD"

# 3. Check for Flutter project marker in directory or parent hierarchy
is_flutter=false
check_dir="$dir"
for _ in {1..5}; do
  if [ -f "$check_dir/pubspec.yaml" ]; then
    if grep -Eqs '(sdk:[[:space:]]*flutter|flutter:[[:space:]]*$|flutter_test:)' "$check_dir/pubspec.yaml"; then
      is_flutter=true
      break
    fi
  fi
  parent="$(dirname "$check_dir")"
  [ "$parent" = "$check_dir" ] && break
  check_dir="$parent"
done

# Check active session flag as secondary fallback
flag_file="$claude_dir/.flutter-active"
if [ "$is_flutter" = false ] && [ -f "$flag_file" ]; then
  is_flutter=true
fi

# 4. Render badge
if [ "$is_flutter" = true ]; then
  printf '\033[38;5;75m[FLUTTER]\033[0m'
else
  printf '\033[38;5;245m[FLUTTER]\033[0m'
fi
