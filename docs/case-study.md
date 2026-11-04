# Case study: the audit script on two public Flutter apps

Date: 2026-11-05. Scanner: `scripts/audit-flutter.sh` from Flutter Ultimate 1.5.0 (Bash 5.3 on Apple Silicon; the PowerShell scanner produced the identical list on LocalSend). Both apps were cloned shallowly at the commits below; nothing was changed in them.

| App | Commit | Dart files (`lib/`) | Lines | Runtime |
| :--- | :--- | ---: | ---: | ---: |
| [LocalSend](https://github.com/localsend/localsend) (`app/`) | `92e133a`, 2026-10-30 | 273 | 122 182 | 6 s |
| [Immich mobile](https://github.com/immich-app/immich) (`mobile/`) | `8e34938`, 2026-11-04 | 616 | 68 028 | 11 s |

The point of the exercise was not to grade the apps. It was to measure the scanner's precision on code written by other teams and to fix what the samples exposed before the release.

## What the first run looked like (1.4.1 scanner)

| Rule | LocalSend | Immich |
| :--- | ---: | ---: |
| K01 | 36 | 17 |
| W01 | 3 | 0 |
| P03 | 0 | 24 |
| P07 | 5 | 11 |
| P12 | 1 | 7 |
| P19 | 1 | 19 |
| P21 | 1 | 4 |
| P26 | 1 | 3 |
| P27 | 3 | 26 |
| P32 | 0 | 11 |
| Total | 51 | 122 |

A random sample of 8 K01 findings on LocalSend classified by reading the code: **2 confirmed, 6 false**. The six false ones fell into three classes:

1. An arrow closure `onTap: () async => await context.push(...)`. Nothing follows the `await` inside the closure, but the scanner resolved the enclosing function to the surrounding `build()` and reported every `Theme.of(context)` after it (4 of the 6).
2. `if (x) { await showDialog(...); } else { await context.pushBottomSheet(...); }`. The `else` branch never runs after the `await` in the `if` branch (1 of 6).
3. `server.setState(...)` on a server object in a non-widget controller, matched as `State.setState` (1 of 6).

A second sample of 10 after fixing those found two more classes: `} else {` on one line (the first fix only handled `else {` on its own line) and a global navigator accessor, `Routerino.context.pushAndRemoveUntilImmediately(...)`, matched by the `context.push` pattern although it is not the widget's context. One finding sat in `test/`.

All five classes are now handled in both scanners, each with a case in `test/fixtures/negative/lib/clean.dart`, and top-level `test/` and `integration_test/` directories are skipped.

## Final run (1.5.0 scanner)

| Rule | LocalSend | Immich | Private 186k-line app (re-run with the 1.5.0 scanner) |
| :--- | ---: | ---: | ---: |
| K01 | 7 | 14 | 124 |
| W01 | 3 | 0 | 70 |
| P03 | 0 | 24 | 38 |
| P07 | 5 | 11 | 176 |
| P12 | 1 | 7 | 4 |
| P19 | 1 | 19 | 29 |
| P21 | 1 | 4 | 10 |
| P26 | 1 | 3 | 13 |
| P27 | 3 | 26 | 85 |
| P32 | 0 | 11 | 12 |
| Total | 22 | 119 | 561 |

### Classification of the CRITICAL findings

**LocalSend, K01, all 7 read:** 7 confirmed, 0 false. Each is a `setState`, `showDialog` or navigation call after an `await` with no mounted check between them. Four of the seven carry the authors' own `// ignore: use_build_context_synchronously` comment, so the team knows about them and accepted the risk; the scanner has no notion of that lint comment and reports them anyway. If you want the same behaviour from the audit, add `// flutter-ultimate:ignore K01 <reason>` above the line.

**LocalSend, W01, all 3 read:** 3 confirmed. Three dialogs create a `TextEditingController` as a field and have no `dispose()` at all.

**Immich, K01, 8 of 17 read before the fixes (first-run sample):** 7 confirmed (`setState` after `await` with no guard, in settings pages and the album selector), 1 was in `test/` and is excluded now. Immich has zero W01 findings: every controller the scanner saw is disposed.

**Private app, K01, 10 of 138 read before the fixes:** 8 confirmed, 2 undetermined (a `Theme.of(context)` deep inside a widget tree built after an `await`, and a `context.pushReplacement` in a router helper), 0 false. **W01, 6 read:** 6 confirmed.

### What this says about precision

On these three codebases the CRITICAL rules, after the fixes, show no false positive in 20 manually read K01 findings and none in 9 W01 findings. That is a small sample, and it is biased: two of the apps are well-maintained open-source projects and the third is one team's style. Different styles will find new holes in a regex scanner; when they do, the procedure is the one used here: sample, classify by reading the code, add the pattern to the negative fixture, fix both scanners, re-run.

The HIGH and lower rules were not sampled. P07 (`MediaQuery.of(context).size`) and P27 (`ClipRRect`) are pattern matches by design and should be read as "look here", not as defects; see the Limitations section in the README.

## Reproduce

```bash
git clone --depth 1 https://github.com/localsend/localsend.git
cd localsend/app
bash /path/to/flutter-ultimate/scripts/audit-flutter.sh --json > localsend.json
```

Then sample with any JSON tool and read the code around each `file:line`. Keep the seed and the list you read; the next release should re-read the same lines.
