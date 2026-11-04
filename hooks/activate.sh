#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"

is_flutter() {
  local dir="$PWD"
  for _i in 1 2 3 4 5; do
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
  cat "$here/mode.md"
else
  echo "flutter-ultimate: loaded. Full mode activates automatically in Flutter workspaces. Commands available: /flutter-review, /flutter-audit."
fi
