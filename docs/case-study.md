# Case study: the audit script on two public Flutter apps

Date: 2026-11-04 (CET). Scanner: `scripts/audit-flutter.sh` from Flutter Ultimate 1.5.0 (Bash 5.3 on Apple Silicon; the PowerShell scanner produced the identical list on LocalSend). Both apps were cloned shallowly at the commits below; nothing was changed in them.

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

**LocalSend, K01, all 7 read:** 7 confirmed, 0 false. Each is a `setState`, `showDialog` or navigation call after an `await` with no mounted check between them. Four of the seven carry the authors' own `// ignore: use_build_context_synchronously` comment, so the team knows about them and accepted the risk. Up to 1.9.0 the scanner reported them anyway; since 1.10.0 `--respect-ignore` leaves them out (see the re-run below). Without that flag, add `// flutter-ultimate:ignore K01 <reason>` above the line.

**LocalSend, W01, all 3 read:** 3 confirmed. Three dialogs create a `TextEditingController` as a field and have no `dispose()` at all.

**Immich, K01, 8 of 17 read before the fixes (first-run sample):** 7 confirmed (`setState` after `await` with no guard, in settings pages and the album selector), 1 was in `test/` and is excluded now. Immich has zero W01 findings: every controller the scanner saw is disposed.

**Private app, K01, 10 of 138 read before the fixes:** 8 confirmed, 2 undetermined (a `Theme.of(context)` deep inside a widget tree built after an `await`, and a `context.pushReplacement` in a router helper), 0 false. **W01, 6 read:** 6 confirmed.

### What this says about precision

On these three codebases the CRITICAL rules, after the fixes, show no false positive in 20 manually read K01 findings and none in 9 W01 findings. That is a small sample, and it is biased: two of the apps are well-maintained open-source projects and the third is one team's style. Different styles will find new holes in a regex scanner; when they do, the procedure is the one used here: sample, classify by reading the code, add the pattern to the negative fixture, fix both scanners, re-run.

The HIGH and lower rules were not sampled. P07 (`MediaQuery.of(context).size`) and P27 (`ClipRRect`) are pattern matches by design and should be read as "look here", not as defects; see the Limitations section in the README.

## Re-run with 1.8.0, 1.9.0 and 1.10.0

Date: 2026-11-20. Same commits as in the table at the top (LocalSend `app/` `92e133a`, Immich `mobile/` `8e34938`), Bash scanner from each release (`git show v1.8.0:scripts/audit-flutter.sh` for 1.8.0), Bash 5.2 on Linux. The PowerShell 1.10.0 scanner produced the identical list on LocalSend with and without `-RespectIgnore`.

| Rule | LocalSend 1.8.0 | LocalSend 1.9.0 | LocalSend 1.10.0 `--respect-ignore` | Immich 1.8.0 | Immich 1.9.0 | Immich 1.10.0 `--respect-ignore` |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| K01 | 7 | 7 | 3 | 14 | 14 | 14 |
| W01 | 3 | 3 | 3 | 0 | 3 | 3 |
| W05 | 0 | 0 | 0 | 0 | 0 | 0 |
| W21 | 0 | 0 | 0 | 0 | 0 | 0 |
| P03 | 0 | 0 | 0 | 24 | 24 | 24 |
| P07 | 5 | 5 | 5 | 11 | 11 | 11 |
| P12 | 1 | 1 | 1 | 7 | 7 | 7 |
| P19 | 1 | 1 | 1 | 19 | 19 | 19 |
| P21 | 1 | 1 | 1 | 4 | 4 | 4 |
| P26 | 1 | 1 | 1 | 3 | 3 | 3 |
| P27 | 3 | 3 | 3 | 26 | 26 | 26 |
| P32 | 0 | 0 | 0 | 11 | 11 | 11 |
| Total | 22 | 22 | 18 | 119 | 122 | 122 |

Without flags, 1.10.0 gives the same records (rule, file, line, message) as 1.9.0 on both apps.

**LocalSend**: 1.8.0 and 1.9.0 give the same list of 22 findings.

**Immich**: the only difference between 1.8.0 and 1.9.0 is three W01 findings in Riverpod `ConsumerState` classes, which 1.9.0 reads: `lib/presentation/widgets/asset_viewer/asset_details/description.widget.dart:23` (`FocusNode`) and `:29` (`TextEditingController`), `lib/presentation/widgets/people/person_edit_name_modal.widget.dart:26` (`TextEditingController`). Neither class has a `dispose()`; 3 of 3 confirmed.

**K01 changes in 1.9.0** (`await` after `(` or `!`, any `Navigator` method, `else` branch of the block that holds the `await` only): the K01 list did not change on either app, no finding added and none lost.

**W05 and W21** (added in 1.8.0) report 0 findings on both apps. These two rules therefore have no precision measurement on public code.

**`--respect-ignore`**: `lib/` in LocalSend has 23 `// ignore: use_build_context_synchronously` comments, Immich `mobile/lib/` has 0. Four of the seven LocalSend K01 findings carry one: three on the line above (`lib/pages/receive_history_page.dart:216`, `lib/util/native/file_picker.dart:188`, `:238`) and one on the next line of a multi-line call (`lib/provider/network/send_provider.dart:280`). With the flag, 3 remain: `lib/widget/dialogs/favorite_edit_dialog.dart:228`, `lib/widget/dialogs/favorite_dialog.dart:54`, `lib/pages/web_share_page.dart:93`. Immich is unchanged.

## Reproduce

```bash
git clone --depth 1 https://github.com/localsend/localsend.git
cd localsend/app
bash /path/to/flutter-ultimate/scripts/audit-flutter.sh --json > localsend.json
```

Then sample with any JSON tool and read the code around each `file:line`. Keep the seed and the list you read; the next release should re-read the same lines.
