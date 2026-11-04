# Impeller, Raster Thread and GPU: Diagnosis Guide

Verified against docs.flutter.dev/perf/impeller and the Flutter 3.47.5 SDK. Trust labels as in `advanced-framework-patterns.md`: Rule / Default / Trade-off / Specialist.

This file is about telling apart four different causes of a slow frame and picking the narrowest fix. The traps P26–P33 in `performance-and-rendering.md` list the APIs; this file says how to prove which one is the problem. Nothing here is a static detector: the scripts flag `Opacity` and `ClipRRect` as MEDIUM / LOW hints only, and no regex can judge GPU cost.

---

## 1. Where the frame time goes (Rule)

| Thread | Work | Symptom in DevTools Performance view | Typical fix |
| :--- | :--- | :--- | :--- |
| UI thread, build | Widget `build()` calls, element reconciliation | Long "Build" slice | Narrow rebuild scope (P1, P2, P8), cache computed values (P13) |
| UI thread, layout | `RenderObject.performLayout`, intrinsic passes | Long "Layout" slice | Remove `IntrinsicHeight` / `shrinkWrap` chains (P19, P21), give bounded constraints |
| UI thread, paint | `paint()` recording display lists | Long "Paint" slice | Cache `Paint` / `Path` (P32), fewer painted items |
| Raster thread | Executing the display list on the GPU: `saveLayer`, blur, clip, shadow, large textures | Long raster bar while the UI bar is short | Shrink the affected area, drop the layer, pre-render the asset |
| GPU wait / memory | Texture uploads, image decode handoff, GPU saturated or throttled | Raster bar long with little drawing work; frames arrive late everywhere | Decode smaller images (P34), fewer live textures, check device thermal state |

A long UI bar and a long raster bar need different fixes. Do not reach for `RepaintBoundary` or `Isolate.run` before you know which bar is long.

## 2. Procedure (Rule)

1. `flutter run --profile` on a physical device of the slowest class you support. Debug mode and simulators are not evidence.
2. Reproduce one scenario (scroll this list, open this sheet) three times, note the device, refresh rate and build mode.
3. Open DevTools Performance view, enable frame analysis, pick the slow frames. Read UI versus raster time first.
4. Form one hypothesis per frame ("the blur behind the app bar repaints on every scroll frame"), change one thing, repeat the same scenario, compare numbers.
5. Keep the simpler code when the difference is not measurable.

When you cannot measure (no device, no profile build), say so: report the finding as a hypothesis and name the measurement that would confirm it. Do not rate it CRITICAL.

## 3. Impeller availability (Rule, verify on docs.flutter.dev/perf/impeller before quoting)

| Platform | Status in Flutter 3.47 | Opt-out |
| :--- | :--- | :--- |
| iOS | Only supported engine | none |
| Android | Default on API 29+; devices below API 29 or without Vulkan fall back to OpenGL ES automatically | `flutter run --no-enable-impeller`; `io.flutter.embedding.android.EnableImpeller` meta-data `false` |
| macOS, Linux, Windows | Default since 3.47; opt-out scheduled for removal | `--no-enable-impeller`; `FLTEnableImpeller` in `Info.plist` / `fl_dart_project_set_enable_impeller` / `set_impeller_switch` |
| Web | Skia (CanvasKit / Skwasm) | not applicable |

What Impeller changes: shaders are precompiled, so the first-use shader-compilation stalls of Skia are gone. What it does not change: layout time, overdraw, the cost of a full-screen `saveLayer`, texture memory, or a GPU that is already saturated. "Impeller is on" is not a reason to skip measurement.

Android devices differ by backend (Vulkan or OpenGL ES) and by GPU family. A frame that is fine on a Pixel can be slow on a mid-range Mali device. Profile on the slow device, not the flagship.

## 4. Compositing cost: hypotheses, not defects (Trade-off)

| Pattern | What makes it expensive | Check before changing |
| :--- | :--- | :--- |
| `Opacity` with a fractional value over a subtree | Subtree is drawn into an offscreen layer and blended back | Is the subtree large? Does it repaint every frame? Static small icons at 0.5 are fine |
| `BackdropFilter` / blur | Reads the content behind it into a texture, blurs it, composites back; cost grows with area and repaint frequency | Is the filter bounded by a `ClipRect`? Does it sit over a scrolling list? |
| `Clip.antiAliasWithSaveLayer`, `ClipPath` on large areas | Offscreen buffer per clip | Is `Clip.antiAlias` (no saveLayer) or a `BoxDecoration` border radius enough? |
| `BoxShadow` with a large blur on many items | Gaussian blur per item per frame | How many shadowed items are on screen at once? Smaller radius, fewer items, or a pre-rendered asset |
| `ShaderMask`, `ColorFiltered`, `ImageFiltered` over animated content | Full-area shader pass per frame | Can the effect be baked into the asset or applied to a smaller widget? |
| Overdraw: several full-screen layers stacked | Every pixel shaded several times | Remove backgrounds that are fully covered |

Rule of thumb for the fix order: shrink the area, then reduce the frequency (do not animate what does not need to move), then replace the effect with an asset, and only then isolate with `RepaintBoundary`. A `RepaintBoundary` stops repaint propagation to neighbours; it costs a layer and memory, and the engine decides whether to cache it, so it is a measured step, not a default.

## 5. Custom painting (Default)

- Build `Path`, `Paint`, gradients and `TextPainter` once (fields or `static final`), not inside `paint()` (P32).
- `shouldRepaint` must compare the inputs; returning `true` repaints every frame.
- Very large paths and dense vector art are tessellated on every paint. For static art, paint once into a `ui.Picture` or an image and draw that; dispose it (W13).
- Draw only what is inside `size`; painting far outside the clip still costs recording time.

## 6. Fragment shaders (Specialist)

- Declare the `.frag` file under `flutter: shaders:` in `pubspec.yaml`; load it once with `FragmentProgram.fromAsset` and keep the `FragmentShader` from `program.fragmentShader()` in a field. Creating the program or shader per frame is the common mistake.
- Update uniforms with `setFloat` / `setImageSampler` on the existing shader each frame; dispose the shader when the owner is disposed.
- Shader cost scales with the painted area. Keep the shaded widget small and measure on the slowest device.
- Shader warm-up (`--bundle-sksl-path`) belongs to the Skia era; with Impeller it is not needed.

## 7. What the agent reports

For a performance finding, state in this order: which thread is long (UI build / layout / paint, raster, GPU wait, or "not measured"), the trace or metric, the widget or drawing path, the narrowest change, and the before / after numbers on the same device and scenario. A finding without a measurement is a hypothesis and is labelled as such.

## 8. Sources

[Impeller](https://docs.flutter.dev/perf/impeller), [Rendering performance](https://docs.flutter.dev/perf/rendering-performance), [DevTools Performance view](https://docs.flutter.dev/tools/devtools/performance), [Fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders), [FragmentProgram](https://api.flutter.dev/flutter/dart-ui/FragmentProgram-class.html).
