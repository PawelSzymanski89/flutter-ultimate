#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const here = __dirname;
const cwd = process.cwd();
const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude');
const flagPath = path.join(claudeDir, '.flutter-active');

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

try {
  if (active) {
    if (!fs.existsSync(claudeDir)) {
      fs.mkdirSync(claudeDir, { recursive: true });
    }
    fs.writeFileSync(flagPath, '1', 'utf8');
  } else if (fs.existsSync(flagPath)) {
    fs.unlinkSync(flagPath);
  }
} catch (e) {}

if (active) {
  const modeFile = path.join(here, 'mode.md');
  if (fs.existsSync(modeFile)) {
    process.stdout.write(fs.readFileSync(modeFile, 'utf8'));
  }
} else {
  process.stdout.write(
    'flutter-ultimate: loaded. Full mode activates automatically in Flutter workspaces. Commands available: /flutter-review, /flutter-audit.\n'
  );
}
