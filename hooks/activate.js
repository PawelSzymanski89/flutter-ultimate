#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const here = __dirname;
const cwd = process.cwd();

function isFlutterProject(dir) {
  let cur = dir;
  for (let i = 0; i < 5; i++) {
    const pubspec = path.join(cur, 'pubspec.yaml');
    if (fs.existsSync(pubspec)) {
      try {
        const content = fs.readFileSync(pubspec, 'utf8');
        // Match Flutter SDK declaration or flutter dependency
        if (/sdk:\s*flutter|flutter:\s*\n|flutter_test:/i.test(content)) {
          return true;
        }
      } catch (e) {}
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return false;
}

const active = isFlutterProject(cwd);

if (active) {
  const modeFile = path.join(here, 'mode.md');
  if (fs.existsSync(modeFile)) {
    process.stdout.write(fs.readFileSync(modeFile, 'utf8'));
  }
} else {
  process.stdout.write(
    'flutter-ultimate: loaded. Full mode activates automatically in Flutter workspaces. Commands available: /flutter-ultimate:flutter-review, /flutter-ultimate:flutter-audit.\n'
  );
}
