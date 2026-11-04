#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
flag_path="$claude_dir/.flutter-active"

is_flutter() {
  local dir="$PWD"
  for _ in {1..5}; do
    if [ -f "$dir/pubspec.yaml" ]; then
      if grep -Eqs '(sdk:[[:space:]]*flutter|flutter:[[:space:]]*$|flutter_test:)' "$dir/pubspec.yaml"; then
        return 0
      fi
    fi
    dir="$(dirname "$dir")"
    [ "$dir" = "/" ] && break
  done
  return 1
}

if is_flutter; then
  mkdir -p "$claude_dir" 2>/dev/null || true
  echo "1" > "$flag_path" 2>/dev/null || true
  cat "$here/mode.md"
else
  rm -f "$flag_path" 2>/dev/null || true
  echo "flutter-ultimate: loaded. Full mode activates automatically in Flutter workspaces. Commands available: /flutter-review, /flutter-audit."
fi
