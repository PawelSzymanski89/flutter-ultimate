#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
flag_path="$claude_dir/.flutter-active"

is_flutter() {
  local dir="$PWD"
  for _ in {1..4}; do
    if [ -f "$dir/pubspec.yaml" ] && grep -qs 'flutter' "$dir/pubspec.yaml"; then
      return 0
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
  echo "flutter-ultimate: loaded. Full mode activates automatically in Flutter projects (pubspec.yaml). Commands available: /flutter-ultimate:audit, /flutter-ultimate:plan, /flutter-ultimate:review."
fi
