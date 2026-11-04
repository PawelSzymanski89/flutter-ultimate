#!/usr/bin/env bash
# Flutter Ultimate statusline: prints [FLUTTER] in blue when the session directory is inside a
# Flutter project (pubspec.yaml with the Flutter SDK), gray otherwise. Plain shell, no node.
#
# Claude Code allows one statusLine command. To keep another statusline in front of this one,
# point FLUTTER_ULTIMATE_STATUSLINE_CHAIN at that script; it receives the same JSON on stdin and
# its output is printed before the badge.
input=$(cat)

if [ -n "${FLUTTER_ULTIMATE_STATUSLINE_CHAIN:-}" ] && [ -f "$FLUTTER_ULTIMATE_STATUSLINE_CHAIN" ]; then
  chained=$(printf '%s' "$input" | bash "$FLUTTER_ULTIMATE_STATUSLINE_CHAIN" 2>/dev/null || true)
  [ -n "$chained" ] && printf '%s ' "$chained"
fi

dir=$(printf '%s' "$input" | sed -nE 's/.*"current_dir"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1)
[ -z "$dir" ] && dir=$(printf '%s' "$input" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1)
[ -z "$dir" ] && dir="$PWD"

is_flutter=false
check_dir="$dir"
for _i in 1 2 3 4 5; do
  if [ -f "$check_dir/pubspec.yaml" ] && grep -Eqs '(sdk:[[:space:]]*flutter|flutter:[[:space:]]*$|flutter_test:)' "$check_dir/pubspec.yaml"; then
    is_flutter=true
    break
  fi
  parent="$(dirname "$check_dir")"
  [ "$parent" = "$check_dir" ] && break
  check_dir="$parent"
done

if [ "$is_flutter" = true ]; then
  printf '\033[38;5;75m[FLUTTER]\033[0m'
else
  printf '\033[38;5;245m[FLUTTER]\033[0m'
fi
