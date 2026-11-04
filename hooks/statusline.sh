#!/usr/bin/env bash
# ==============================================================================
# Flutter Ultimate Statusline Indicator
# Displays [PONYTAIL] (if active) + [FLUTTER] badge in the bottom status line:
# - Bright blue (\033[38;5;75m) when workspace is inside a Flutter project
# - Subtle gray (\033[38;5;245m) otherwise
# ==============================================================================
input=$(cat)

# 1. Chain Ponytail statusline & extract workspace dir in a single Node process
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
meta=$(printf '%s' "$input" | node -e '
  const fs = require("fs");
  const path = require("path");
  let pony = "";
  let dir = "";
  try {
    const claudeDir = process.argv[1] || "";
    const base = path.join(claudeDir, "plugins/cache/ponytail/ponytail");
    if (fs.existsSync(base)) {
      const dirs = fs.readdirSync(base).sort((a,b) => a.localeCompare(b, undefined, {numeric: true}));
      for (let i = dirs.length - 1; i >= 0; i--) {
        const p = path.join(base, dirs[i], "hooks/ponytail-statusline.sh");
        if (fs.existsSync(p)) { pony = p; break; }
      }
    }
    if (!pony) {
      const fallback = path.join(claudeDir, "ponytail-statusline.sh");
      if (fs.existsSync(fallback)) pony = fallback;
    }
    const raw = fs.readFileSync(0, "utf8");
    if (raw) {
      const obj = JSON.parse(raw);
      dir = (obj.workspace && obj.workspace.current_dir) || obj.cwd || "";
    }
  } catch(e) {}
  process.stdout.write((pony || "-") + "\t" + (dir || "-"));
' "$claude_dir" 2>/dev/null || printf -- "-\t-")

pony="${meta%%	*}"
dir="${meta#*	}"
[ "$pony" = "-" ] && pony=""
[ "$dir" = "-" ] && dir=""

if [ -n "$pony" ] && [ -f "$pony" ]; then
  pony_out=$(printf '%s' "$input" | bash "$pony" 2>/dev/null || true)
  if [ -n "$pony_out" ]; then
    printf '%s ' "$pony_out"
  fi
fi

[ -z "$dir" ] && dir="$PWD"

# 2. Check for Flutter project marker in directory or parent hierarchy
is_flutter=false
check_dir="$dir"
for _i in 1 2 3 4 5; do
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

# 3. Render badge
if [ "$is_flutter" = true ]; then
  printf '\033[38;5;75m[FLUTTER]\033[0m'
else
  printf '\033[38;5;245m[FLUTTER]\033[0m'
fi
