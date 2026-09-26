# Architecture

How Veneer puts native UIKit UI in a Flutter app, what it measured, and the rules it learned.

## The overlay

Veneer doesn't embed a platform view per widget. It adds **one** transparent view above the
`FlutterView` and keeps it in sync with Flutter layout:

```
UIWindow
└─ FlutterView                      Flutter draws the app here
   └─ VeneerOverlayView             touch-transparent except on native targets
      ├─ GlassLayerView             stacks glass groups by zIndex
      │  └─ GlassGroupView          merge boundary (GlassGroup, or the route's default group)
      │     └─ GlassClipScopeView   one per Flutter clip: a mask + UIGlassContainerEffect
      │        └─ GlassShapeView    UIGlassEffect, one per GlassShape widget
      ├─ UIScrollView (clear)       hosts iOS 26's scroll edge effect over Flutter content
      ├─ UITabBarController.view    a real tab bar controller (child of the FlutterViewController)
      │                             whose tabs are empty and touch-transparent
      ├─ UINavigationBar            the navigation bar
      └─ Composer                   NativeComposerView or NativePromptComposerView (one at a time)
```

Glass samples whatever is composited beneath it, so it refracts Flutter's pixels exactly as it
would refract UIKit content. Shapes in the same group share one `UIGlassContainerEffect`, so
separate Flutter widgets merge and morph into each other — impossible when each widget is its
own platform view.

**Hit testing** asks each layer separately, top to bottom: the composer, the navigation bar,
the tab bar, then interactive glass. Anything else falls through to Flutter.

## Per-frame geometry

Glass must move in the same frame as the Flutter content under it.

1. A persistent frame callback runs after the renderer's, so it sees the final layout of the
   frame just composited.
2. It resolves each `RenderGlassAnchor`'s rect, paint visibility and clips in one walk up the
   render tree (`resolveAnchorGeometry`), composing transforms as `getTransformTo(null)` does.
   It can't use `paint`: scrolling moves repaint-boundary layers without repainting the anchor.
3. It writes everything into a native-owned `Float64List` (`asTypedList`, no copy) and makes a
   **synchronous, non-leaf** `dart:ffi` call. With merged UI and platform threads (the default
   on iOS) the call runs on the main thread inside the Flutter frame.
4. Native code sets `UIView` frames directly. They commit with the run loop's implicit
   `CATransaction`, together with Flutter's frame.

The same buffer carries one extra entry: how far the active composer's page has moved from its
resting position, so a composer rides a route transition in the same frame.

Buffer layout: `[frameNumber, count, entry × count]`, each entry 20 doubles — id, rect (LTWH),
visible, clip id, clip flags, clip rect, clip rounded rect, four corner radii.

## Chrome

Chrome is configured from Dart but laid out and animated by UIKit.

- **Tab bar:** a real `UITabBarController` whose tabs host empty view controllers; Flutter draws
  the pages underneath. The trailing button is a `UISearchTab`, which UIKit detaches at the
  trailing edge (iOS 27 also requires it to be the `prominentTabIdentifier`). Its height goes
  into `MediaQuery` padding so content scrolls under it.
- **Navigation bar:** a real `UINavigationBar`. Items are replaced only when their part of the
  config changes, animated so UIKit morphs the glass.
- **Scroll edge effect:** UIKit attaches `UIScrollEdgeEffect` to scroll views, which Flutter
  doesn't use. A transparent, non-interactive scroll view spans the overlay, parked so its
  edges are active, and the bars register through `UIScrollEdgeElementContainerInteraction`,
  which shapes the effect around their controls.
- **Composers:** share a base view (text view, focus, send, menus). Their morphs run inside the
  keyboard notification's animation, with its duration and curve. The keyboard frame is kept in
  screen coordinates and converted at layout time, because the composer's view can move while
  the keyboard is up (a sheet growing to its large detent).
- **Interactive keyboard dismissal:** UIKit only drives it from a scroll view's pan. An
  invisible scroll view with `keyboardDismissMode = .interactive` has its pan gesture attached
  to the `FlutterView` with `cancelsTouchesInView = false`, so Flutter still scrolls, and the
  composer follows `keyboardLayoutGuide`, which UIKit updates frame by frame during the drag.

Only config that changes is sent: pages rebuild every frame while the keyboard animates.

## Native sheets

A Flutter engine renders into one view at a time, so a native sheet runs its own engine:

1. `showNativeSheet(entrypoint:)` asks the plugin to present. The engine comes from a shared
   `FlutterEngineGroup` (shared compiled code and GPU context), pre-warmed at that entrypoint
   when possible. Plugins are registered in it through the app's `GeneratedPluginRegistrant`,
   found at runtime.
2. A `FlutterViewController` on that engine is presented with `.pageSheet`. Its view is
   transparent, so the sheet's own Liquid Glass shows through the content.
3. Veneer's plugin instance in the sheet's engine attaches an overlay to the sheet's view, so
   bars and composers inside it are native and move with the sheet.
4. Dismissal and detent changes go back to the presenting engine, completing
   `showNativeSheet`'s future with `NativeSheet.close`'s result.

Each engine has its own plugin instance, frame buffer and overlay; the FFI call carries the
plugin id.

**Dragging over content:** a UIKit sheet drags when no scroll view claims the touch. On every
touch, the sheet's Flutter app reports whether the scrollable under the finger is at its top
edge. Veneer's scroll view then claims only the drags that belong to the content, and pulls
down at the top edge — or pushes up below the largest detent — are left to the sheet.

## Fallbacks

`VeneerBridge.isSupported` is true on iOS 26+. Elsewhere, and under a `VeneerFallbackScope`,
every widget renders a Flutter replica built from the native metrics (`VeneerFallbackStyle`
holds the iOS system colours and surfaces). The Flutter sheet (`NativeSheetRoute`) wraps its
content in a fallback scope, since native views can't follow a sheet Flutter draws.

## Results (iPhone simulator, iOS 27, debug build)

| Check | Result |
|---|---|
| Glass vs Flutter offset at 1200 pt/s scroll, FFI | median 0.17 pt (≈ 1 px); one frame of scroll is 20 pt |
| Same, async method channel | median 0.17 pt |
| Same, control: channel delayed 16 ms | median 27 pt (≈ 1.4 frames), so the harness detects lag |
| FFI apply on the main thread | 100% |
| Native apply cost | average 0.07 ms, max 0.5 ms (10 shapes) |
| Composer morph, idle ⇄ focused | about 0.4 s each way, keyboard-synced (checked frame by frame) |
| Prompt composer, voice mode split | about 0.45 s spring (checked frame by frame) |
| Interactive keyboard dismissal | keyboard and composer follow the finger, then dismiss or snap back |
| Native sheet | detents, drag from content, keyboard growth to large, close with result |

On the simulator both transports land in the same frame: with merged threads a channel message
is handled before Core Animation commits. FFI doesn't depend on task-queue ordering and has no
codec overhead. Real-device measurements (ProMotion, release builds) are still to come.

To measure:

```bash
xcrun simctl launch --terminate-running-process <udid> dev.veneer.example -VENEER_TRANSPORT ffi -VENEER_MEASURE 1
python3 tool/measure_sync.py <udid> 20
```

`-VENEER_TRANSPORT` accepts `ffi`, `channel` or `delayedChannel`; always run `delayedChannel`
as the control.

## Rules learned (each was a bug)

- **Never force a layout pass inside the FFI call.** A top-level `CATransaction.commit()` or
  `UIView.animate` flushes window layout, which reaches `FlutterViewController` and re-enters
  Dart synchronously. Under a leaf call this deadlocks, intermittently, at cold start. The
  apply only writes frames and moves views; visibility animations are deferred.
- **Don't make the FFI call a leaf call**, for the same reason.
- **Animate `effect`, never `alpha`, on `UIVisualEffectView`.** Glass with alpha below 1 renders
  incorrectly.
- **Hidden or non-interactive shapes must return nil from `hitTest`**, or an offstage page's
  shape shadows the button above it.
- **Full-screen containers must be hit-test transparent**, and each overlay layer is hit-tested
  separately: the tab bar controller's empty full-screen view would otherwise swallow touches.
- **Glass ignores masks on its own views.** A mask on an ordinary `UIView` ancestor clips it,
  hence one wrapper per clip scope.
- **Resolve colours on bright tinted glass yourself.** Glass tinted white switches its content
  to the light appearance, so a dynamic `systemBackground` glyph turns white on white.
- **Check the composer's frame before hit-testing it.** While its text view is first responder,
  UIKit resolves hits to text-interaction views far outside it.
- **Check visibility against the live route.** A page covered by a new route can rebuild before
  it hears it's no longer current, and must not take the native view back.
- **Order composer hosts by activation.** A covered page can re-attach mid-transition (when the
  route above wraps it in a transition) and must not steal the composer.
- **Keep the keyboard frame in screen space.** A view inside a sheet moves while the keyboard is up.
- **Icon fonts need correct side bearings.** Rasterizers place a glyph by its left side bearing;
  a wrong value shifts every icon sideways.
- **`IndexedStack` doesn't override `paintsChild`.** Use `Visibility.of(context)`.
- **Attach the tab bar delegate after the initial selection**, and flag programmatic selections:
  UIKit calls the delegate for them too.

## Package layout

```
lib/
  veneer.dart                     public API
  src/core/                       veneer_bridge.dart (FFI + channel), native_icon.dart,
                                  native_menu.dart, fallback_scope.dart, fallback_style.dart,
                                  anchor_geometry.dart
  src/glass/                      glass_shape.dart, glass_group.dart, glass_coordinator.dart
  src/chrome/                     native_chrome.dart (tab bar), native_navigation_bar.dart,
                                  native_composer.dart (+ native_prompt_composer.dart),
                                  native_sheet.dart
ios/veneer/Sources/veneer/
  VeneerPlugin.swift              channel, FFI entry point, per-engine instances
  Core/                           VeneerOverlayView, NativeIcon, SVGIcon, SVGPathParser, SVGValues
  Glass/                          GlassLayerView, GlassShapeView, ShapeClip
  Chrome/                         NativeTabBarHost, NativeNavigationBarHost, ComposerBaseView,
                                  NativeComposerView, NativePromptComposerView,
                                  NativeSheetPresenter, ScrollEdgeEffectHost, KeyboardDismissProxy
```
