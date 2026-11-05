# Accessibility: Semantics, Contrast, Tap Targets and Text Scaling

Verified against the Flutter 3.47.5 SDK (`packages/flutter_test/lib/src/accessibility.dart` for the guideline constants, `Semantics` / `SemanticsProperties` in `flutter/widgets`, `MediaQuery.textScalerOf`) and docs.flutter.dev/ui/accessibility-and-internationalization/accessibility. Trust labels: Rule / Default / Trade-off / Specialist.

Nothing in this file is a static detector. The scanner cannot see a missing label or a 3:1 contrast; the checks below run in widget tests or by hand with a screen reader. Keep "the test says" apart from "I read the widget" in every report, as in `testing-and-reliability.md`.

---

## 1. What the platform reads (Rule)

Flutter builds a semantics tree next to the render tree. Screen readers (TalkBack on Android, VoiceOver on iOS, the platform bridges on desktop and web) see only that tree. Standard widgets (`ElevatedButton`, `Checkbox`, `TextField`, `Slider`, `Image` with `semanticLabel`) fill it in; a `GestureDetector` around a `Container` with an icon fills in nothing. That is the most common gap: a tappable thing with no role and no label.

| Situation | What the screen reader gets | Fix |
| :--- | :--- | :--- |
| `GestureDetector` / `InkWell` around a bare icon or image | A node with an `onTap` action and no label | `Semantics(button: true, label: '...', child: ...)` or use `IconButton(tooltip: ...)` |
| `Icon(Icons.delete)` without `semanticLabel` | Nothing, the icon is invisible | `Icon(..., semanticLabel: 'Delete')`; for a button prefer the `tooltip` which doubles as the label |
| `Image` without `semanticLabel` | Nothing | `semanticLabel` for content images, `excludeFromSemantics: true` for decoration |
| A card made of a title, a subtitle and a price | Three separate stops | `MergeSemantics` so the card reads as one sentence |
| A custom `CustomPaint` control | Nothing | `Semantics` with `label`, `value`, `increasedValue` / `decreasedValue`, `onIncrease` / `onDecrease` |
| A live counter, upload progress, error banner | Changes go unnoticed | `Semantics(liveRegion: true, ...)` for content that should be announced when it changes |
| Decorative overlay that duplicates visible text | The text read twice | `ExcludeSemantics` on the decorative copy |

`SemanticsService.announce(message, textDirection)` is for events with no widget to attach them to (an undo completed in the background). Prefer `liveRegion` on the widget that shows the change; an announcement is a side effect the user cannot find again.

## 2. Semantics checklist for a review (Default)

- Every element with `onTap` / `onLongPress` has a label (`labeledTapTargetGuideline` fails otherwise).
- Buttons are buttons: `button: true` on custom controls, or a Material / Cupertino button widget.
- Headers carry `header: true` so the user can jump between sections.
- Form fields: `TextField(decoration: InputDecoration(labelText: ...))`; a hint alone disappears when the field is filled. Error text is read when `errorText` is set.
- Toggle state is exposed (`Checkbox`, `Switch`, or `Semantics(toggled: ...)` / `checked:`), not just a colour change.
- Images: `semanticLabel` for content, excluded for decoration. Do not describe the picture when the caption next to it already does.
- Traversal order follows the visual order. When it does not (overlays, custom layouts), `Semantics(sortKey: OrdinalSortKey(n))` fixes it; this is a Trade-off, reorder the tree first.
- Focus: keyboard and switch-control users reach every control; `FocusTraversalGroup` scopes the order, `Focus(skipTraversal: true)` removes a non-interactive node.
- Dialogs and sheets: the first focus lands on the dialog content; after `pop`, focus returns to the trigger (Material handles this for `showDialog`; custom overlays need `FocusScope`).

## 3. Contrast (Rule for the numbers, measured in tests)

`textContrastGuideline` in `flutter_test` implements WCAG AA. The constants in the SDK:

| Text | Minimum ratio |
| :--- | ---: |
| Normal text | 4.5 : 1 |
| Large text: at least 18 pt, or bold and at least 14 pt | 3.0 : 1 |

`MinimumTextContrastGuidelineAAA` raises these to 7 : 1 and 4.5 : 1. Disabled controls are exempt. The guideline samples the rendered pixels of each text node against the pixels behind it, so a text on a gradient or an image is measured where it sits, and a transparent background is measured against what shows through.

Contrast also applies to icons and control outlines against their background (docs.flutter.dev states 4.5 : 1 for controls and text; the SDK guideline tests text only). Check a custom icon button on a tinted background by hand or with `CustomMinimumContrastGuideline`.

Non-text defaults worth knowing: Material 3 `ColorScheme` pairs (`primary` / `onPrimary`, `surface` / `onSurface`) are built to pass AA. Custom hex colours from a design file are the usual failure; test the theme once in a widget test and the per-screen tests inherit it.

## 4. Tap targets (Rule)

| Platform guideline | Minimum size |
| :--- | ---: |
| `androidTapTargetGuideline` | 48 × 48 logical pixels |
| `iOSTapTargetGuideline` | 44 × 44 logical pixels |

The guideline measures the semantics node's rectangle, so an `IconButton` with a 24 px icon passes through its default 48 px constraints, and a bare `GestureDetector` around a 20 px icon fails. Fixes in order: use the Material button (it already pads), `IconButton(constraints: ...)`, `Padding` inside the tappable area (not outside it), `MaterialTapTargetSize.padded` (the default; `shrinkWrap` removes the padding and is the thing to look for when a dense toolbar fails). Targets at the screen edge count the edge as a boundary.

## 5. Text scaling (Rule)

Users set text size at the OS level, up to about 200 % on both platforms and more with accessibility settings. Read it with `MediaQuery.textScalerOf(context)` (a `TextScaler`; the old `textScaleFactor` double is deprecated). `Text` applies it by default. What breaks:

- Fixed-height containers around text (`SizedBox(height: 48, child: Text(...))`) clip at 150 %. Let the text size the box, or use `ConstrainedBox(minHeight:)`.
- `Row` with text and no `Expanded` / `Flexible` overflows. Wrap the text.
- `BottomNavigationBar` / `NavigationBar` labels, chips and badges: test at 200 %, that is where they wrap or clip.
- Icon-only buttons do not scale; the hit target stays 48 px, which is fine, but icon-and-text pairs become unbalanced. `Icon(size:)` can read the scaler if the design needs it.
- Clamping (`MediaQuery(data: data.copyWith(textScaler: TextScaler.linear(1.3)))`) is a Trade-off: it keeps the layout but overrides the user's choice. Clamp a single dense widget, never the whole app, and say so in the review.

Test with `tester.platformDispatcher.textScaleFactorTestValue` or by wrapping the widget under test in a `MediaQuery` with `textScaler: const TextScaler.linear(2.0)` and asserting no overflow (`tester.takeException()` is `null`).

## 6. Widget tests (Default when the project has widget tests)

```dart
testWidgets('settings page meets accessibility guidelines', (tester) async {
  final handle = tester.ensureSemantics(); // builds the semantics tree for this test
  await tester.pumpWidget(const App(home: SettingsPage()));

  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

  handle.dispose(); // the test fails with a pending semantics handle otherwise
});
```

Four guidelines, one call each. `ensureSemantics` returns a `SemanticsHandle` that must be disposed; `addTearDown(handle.dispose)` right after creating it is the safe form. Run these on the screens with custom controls, not on every screen; the standard widgets pass by construction and the test time adds up.

Reading a failure: the matcher names the node, its rectangle and the measured value ("expected contrast ratio of at least 4.5 but found 3.2 for a text of size 14.0"). The widget is identified by its label or its `Key`, so controls without either are hard to find; that is itself a finding.

## 7. Manual pass (Rule before a release that touches navigation or forms)

1. Turn on TalkBack or VoiceOver, swipe through the screen from top to bottom. Every stop should say what it is and what it does; "button" with no name is a defect.
2. Set text size to the largest OS setting, open the same screens, look for clipped or overlapping text.
3. Android Settings > Accessibility > Colour correction, or the iOS grayscale filter: is state still visible without colour?
4. Flutter inspector: enable "Show Semantics" (or `debugDumpSemanticsTree()`) to see what the tree contains; `MaterialApp(showSemanticsDebugger: true)` draws it on the device.

## 8. What the agent reports

For an accessibility finding: the widget (`file:line`), which of the four guideline classes it fails or which checklist row it misses, the measured value when it comes from a test, and the smallest change (a `semanticLabel`, a `MergeSemantics`, a wrapped `Row`). "No semantics" on a decorative element is not a finding. Contrast numbers quoted without a test run are estimates and are labelled as such.

## 9. Sources

[Accessibility (docs.flutter.dev)](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility), [AccessibilityGuideline](https://api.flutter.dev/flutter/flutter_test/AccessibilityGuideline-class.html), [MinimumTextContrastGuideline](https://api.flutter.dev/flutter/flutter_test/MinimumTextContrastGuideline-class.html), [Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html), [SemanticsProperties](https://api.flutter.dev/flutter/semantics/SemanticsProperties-class.html), [MergeSemantics](https://api.flutter.dev/flutter/widgets/MergeSemantics-class.html), [SemanticsService](https://api.flutter.dev/flutter/semantics/SemanticsService-class.html), [TextScaler](https://api.flutter.dev/flutter/painting/TextScaler-class.html), [WidgetTester.ensureSemantics](https://api.flutter.dev/flutter/flutter_test/WidgetTester/ensureSemantics.html), [WCAG 2.1 contrast minimum](https://www.w3.org/TR/WCAG21/#contrast-minimum).
