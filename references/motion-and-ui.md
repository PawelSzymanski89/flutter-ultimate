# Motion, UI Architecture & Fluid Interactions Reference

This blueprint defines standards for 60/120 FPS render pipelines, physics-based animations, advanced slivers, micro-interactions, and design token hierarchies in Flutter.

---

## 1. 60/120 FPS Render Pipelines & Performance Invariants

Flutter targets a strict frame budget:
- **60 FPS**: 16.6 milliseconds per frame.
- **120 FPS (ProMotion / High Refresh Rate)**: 8.33 milliseconds per frame.

A dropped frame (jank) occurs when the combined execution time of the **UI thread** (Widget build, layout calculation, paint recording) and the **Raster thread** (GPU command rendering) exceeds this budget.

### 1.1 The Layout vs. Paint Boundary Rule
- Re-layout cascades down and up the RenderObject tree. Changing layout properties (`width`, `height`, `margin`, `padding`) inside an unconstrained animation forces recursive layout passes across ancestor and descendant nodes.
- Re-paint is cheaper than re-layout. Transforming paint properties (`Transform`, `Opacity`, `ColorFilter`) touches only the painting phase.
- **RepaintBoundary**: Place `RepaintBoundary` widgets around subtrees that animate frequently (e.g., spinning loaders, radar sweeps, physics springs). This isolates the animated `RenderObject` into its own layer cache and prevents repainting static ancestors.

```dart
// Isolating high-frequency animation paint passes
Widget buildOptimizedPulse({required Widget child}) {
  return RepaintBoundary(
    child: AnimatedScale(
      scale: 1.05,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: child,
    ),
  );
}
```

### 1.2 The `saveLayer` Trap
Using `Opacity`, `ShaderMask`, or `ColorFiltered` with unoptimized settings calls the Skia/Impeller `saveLayer` primitive. `saveLayer` allocates an off-screen texture buffer, switches GPU render targets, and composites the texture back into the main framebuffer.
- **Rule**: Never wrap a large widget subtree in `Opacity`. Use `AnimatedOpacity` only when animating alpha. For static transparency, apply the alpha channel directly to the widget's `Color` (e.g., `theme.colorScheme.primary.withValues(alpha: 0.8)`).

---

## 2. Visually Stunning UX & Animation Mechanics

### 2.1 Implicit Animations vs. Explicit Controllers
- **Implicit Animations** (`AnimatedContainer`, `AnimatedScale`, `AnimatedOpacity`, `AnimatedPadding`, `AnimatedSlide`, `AnimatedRotation`):
  Use when state transitions are triggered declaratively by external state changes. The Flutter framework automatically calculates tweens from the old value to the new value over the specified `duration` and `curve`.
- **Explicit Animations** (`AnimationController`, `TickerProviderStateMixin`, `CurvedAnimation`):
  Use when the animation loops continuously, requires manual scrubbing/reverse control, or must be synchronized with physics simulations or continuous drag gestures.

### 2.2 Physics-Based Curves & Spring Simulations

Standard linear or bezier curves can feel mechanical. Physics-based springs account for mass, stiffness, and damping, providing natural tactile feedback.

#### Natural Curves
- `Curves.easeOutCubic`: Ideal for entrance transitions. Decelerates naturally as it approaches rest.
- `Curves.fastOutSlowIn`: Standard Material deceleration curve for modal elements and sheets.

#### Custom Spring Simulations
Use `SpringDescription` and `SpringSimulation` to handle gesture release velocity without visual snapping.

```dart
import 'package:flutter/physics.dart';

class SpringPullCard extends StatefulWidget {
  final Widget child;
  const SpringPullCard({super.key, required this.child});

  @override
  State<SpringPullCard> createState() => _SpringPullCardState();
}

class _SpringPullCardState extends State<SpringPullCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Alignment _dragAlignment;
  late Animation<Alignment> _animation;

  // Spring constants: critically damped or slightly underdamped
  final _spring = const SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 20.0,
  );

  @override
  void initState() {
    super.initState();
    _dragAlignment = Alignment.center;
    _controller = AnimationController(vsync: this);
    _controller.addListener(() {
      setState(() {
        _dragAlignment = _animation.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSpringAnimation(Offset pixelsPerSecond, Size size) {
    _animation = _controller.drive(
      AlignmentTween(
        begin: _dragAlignment,
        end: Alignment.center,
      ),
    );

    // Normalize velocity to alignment coordinate space (-1.0 to 1.0)
    final unitsPerSecondX = pixelsPerSecond.dx / size.width;
    final unitsPerSecondY = pixelsPerSecond.dy / size.height;
    final unitVelocity = Offset(unitsPerSecondX, unitsPerSecondY);
    final visualVelocity = unitVelocity.distance;

    final simulation = SpringSimulation(_spring, 0.0, 1.0, -visualVelocity);
    _controller.animateWith(simulation);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return GestureDetector(
      onPanDown: (_) => _controller.stop(),
      onPanUpdate: (details) {
        setState(() {
          _dragAlignment += Alignment(
            details.delta.dx / (size.width / 2),
            details.delta.dy / (size.height / 2),
          );
        });
      },
      onPanEnd: (details) {
        _runSpringAnimation(details.velocity.pixelsPerSecond, size);
      },
      child: Align(
        alignment: _dragAlignment,
        child: widget.child,
      ),
    );
  }
}
```

---

## 3. CustomScrollView & Slivers Mastery

Slivers are portions of a scrollable area that implement lazy, view-port budgeted rendering. They calculate layout lazily based on `SliverConstraints` and `SliverGeometry`.

### 3.1 Pinned & Floating `SliverAppBar` Dynamics
To create engaging headers, configure floating and pinned dynamics:
- `floating: true`: Header reappears immediately as soon as the user scrolls up.
- `pinned: true`: Header stays pinned to the top of the viewport when scrolling down.
- `snap: true`: Snaps completely open or closed once floating starts.
- `stretch: true`: Allows overscroll stretching on iOS/Android overscroll bouncers.

```dart
Widget buildSliverHeader(BuildContext context) {
  final theme = Theme.of(context);
  return SliverAppBar(
    expandedHeight: 220.0,
    floating: false,
    pinned: true,
    stretch: true,
    backgroundColor: theme.colorScheme.surface,
    elevation: 0,
    flexibleSpace: FlexibleSpaceBar(
      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(
        'Portfolio Overview',
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
      background: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surface,
            ],
          ),
        ),
      ),
      stretchModes: const [
        StretchMode.zoomBackground,
        StretchMode.blurBackground,
      ],
    ),
  );
}
```

### 3.2 Custom `SliverPersistentHeaderDelegate`
Use `SliverPersistentHeader` to pin dynamic sticky tab bars, search fields, or filter chips.

```dart
class StickyFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const StickyFilterHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final isPinned = shrinkOffset > 0 || overlapsContent;

    return Material(
      elevation: isPinned ? 2.0 : 0.0,
      color: theme.colorScheme.surface,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      child: SizedBox(
        height: height,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant StickyFilterHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
```

### 3.3 Lazy Virtualized Lists with Staggered Entrance
Never build full lists upfront. Use `SliverList.separated` or `SliverChildBuilderDelegate` with `findChildIndexCallback` for efficient item recycling.

```dart
Widget buildVirtualizedStaggeredList({
  required List<String> items,
}) {
  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        final item = items[index];
        return StaggeredListItem(
          index: index,
          child: ListTile(
            title: Text(item),
            subtitle: Text('Index $index'),
          ),
        );
      },
      childCount: items.length,
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final idx = items.indexOf(key.value);
          return idx != -1 ? idx : null;
        }
        return null;
      },
    ),
  );
}

class StaggeredListItem extends StatefulWidget {
  final int index;
  final Widget child;

  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    // Stagger item entrance by 30ms increments, capping at 300ms
    final delay = Duration(milliseconds: (widget.index * 30).clamp(0, 300));
    Future.delayed(delay, () {
      if (mounted) {
        setState(() => _isVisible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      opacity: _isVisible ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        offset: _isVisible ? Offset.zero : const Offset(0.0, 0.15),
        child: widget.child,
      ),
    );
  }
}
```

---

## 4. Micro-Interactions, Tactile Feel & Transitions

### 4.1 Platform Haptic Feedback Invariants
Haptic feedback anchors user touch events in physical space.
- `HapticFeedback.lightImpact()`: Trigger on non-destructive micro-actions (tab switch, chip toggle, pull-to-refresh detent threshold).
- `HapticFeedback.mediumImpact()`: Trigger on primary actions (slider detent, drawer snap, card swipe completion).
- `HapticFeedback.heavyImpact()`: Trigger on long-press context menu reveal, deletion actions.
- `HapticFeedback.selectionClick()`: Trigger on picker scroll wheel increments.

```dart
void onFilterSelected(String filter) {
  HapticFeedback.lightImpact();
  // Update filter state
}

void onCriticalDelete() {
  HapticFeedback.heavyImpact();
  // Execute deletion
}
```

### 4.2 Hero Transitions with `flightShuttleBuilder`
Standard `Hero` widgets can distort text formatting, border radii, or aspect ratios mid-flight. Use `flightShuttleBuilder` to interpolate shapes and typography smoothly.

```dart
Widget buildHeroCard({
  required String tag,
  required Widget child,
}) {
  return Hero(
    tag: tag,
    flightShuttleBuilder: (
      flightContext,
      animation,
      flightDirection,
      fromHeroContext,
      toHeroContext,
    ) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );

      return AnimatedBuilder(
        animation: curvedAnimation,
        builder: (context, _) {
          return Material(
            color: Colors.transparent,
            child: DefaultTextStyle.merge(
              style: TextStyle.lerp(
                Theme.of(fromHeroContext).textTheme.titleMedium,
                Theme.of(toHeroContext).textTheme.headlineMedium,
                curvedAnimation.value,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.lerp(
                  BorderRadius.circular(16.0),
                  BorderRadius.circular(0.0),
                  curvedAnimation.value,
                )!,
                child: toHeroContext.widget,
              ),
            ),
          );
        },
      );
    },
    placeholderBuilder: (context, heroSize, child) {
      // Prevent layout shift during flight
      return SizedBox(
        width: heroSize.width,
        height: heroSize.height,
        child: Opacity(opacity: 0.15, child: child),
      );
    },
    child: child,
  );
}
```

---

## 5. Design Token Hierarchy & Theme Extensions

Hardcoding spacing constants, border radii, or colors leads to design inconsistencies and breaks dynamic theming.

### 5.1 Design Tokens Contract
```dart
abstract final class AppSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double s = 12.0;
  static const double m = 16.0;
  static const double l = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

abstract final class AppRadii {
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double full = 999.0;
}
```

### 5.2 Type-Safe `ThemeExtension`
Extend `ThemeData` without monkey-patching or relying on static globals:

```dart
@immutable
class ExtendedColors extends ThemeExtension<ExtendedColors> {
  final Color success;
  final Color warning;
  final Color chartAccent;

  const ExtendedColors({
    required this.success,
    required this.warning,
    required this.chartAccent,
  });

  @override
  ExtendedColors copyWith({
    Color? success,
    Color? warning,
    Color? chartAccent,
  }) {
    return ExtendedColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      chartAccent: chartAccent ?? this.chartAccent,
    );
  }

  @override
  ExtendedColors lerp(ThemeExtension<ExtendedColors>? other, double t) {
    if (other is! ExtendedColors) return this;
    return ExtendedColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      chartAccent: Color.lerp(chartAccent, other.chartAccent, t)!,
    );
  }
}

// Extension helper for clean context access
extension ExtendedThemeContext on BuildContext {
  ExtendedColors get extendedColors =>
      Theme.of(this).extension<ExtendedColors>() ??
      const ExtendedColors(
        success: Color(0xFF10B981),
        warning: Color(0xFFF59E0B),
        chartAccent: Color(0xFF6366F1),
      );
}
```
