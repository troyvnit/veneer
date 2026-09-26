# veneer (prototype)

A thin layer of real native iOS UI over Flutter, without a platform view per widget.

Veneer keeps **one** native overlay above the Flutter surface and lets Flutter
layout drive it every frame. The first two features are native chrome (a UIKit tab bar)
and iOS 26+ Liquid Glass. The same anchor-and-overlay core is meant to carry
other native UI later.

```
UIWindow
└─ FlutterView  (Flutter's Metal layer draws your app here)
   └─ VeneerOverlayView            ← touch-transparent except on native targets
      ├─ GlassLayerView            ← stacks groups by zIndex
      │  ├─ GlassGroupView         ← merge boundary (GlassGroup / route default)
      │  │  ├─ GlassClipScopeView  ← one per Flutter clip: mask + UIGlassContainerEffect
      │  │  │  ├─ GlassShapeView (UIGlassEffect)  ← one per GlassShape widget
      │  │  │  └─ …
      │  │  └─ GlassClipScopeView (unclipped) …
      │  └─ GlassGroupView (zIndex 1) …
      └─ UITabBarController.view   ← native chrome: a real tab bar controller (child of
                                     the FlutterViewController) with empty, touch-transparent tabs
```

Glass samples whatever is composited beneath it, so it refracts Flutter
pixels. Shapes in the same group share one container, so separate widgets **merge and
morph** into each other. That can't happen when each widget is its own platform view.

## Native tab bar (with split layout)

```dart
NativeChromeScope(
  tabs: const [
    NativeTabItem(title: 'Home', icon: NativeIcon.symbol('house'), selectedIcon: NativeIcon.symbol('house.fill')),
    NativeTabItem(title: 'Likes', icon: NativeIcon.icon(Icons.favorite_border), badge: '3'),
    NativeTabItem(title: 'Cut', icon: NativeIcon.svgAsset('assets/icons/scissors.svg')),
  ],
  trailingAction: NativeTabAction(icon: NativeIcon.icon(Icons.add), title: 'New', onPressed: compose),
  selectedIndex: index,
  onTabSelected: (i) => setState(() => index = i),
  child: pages,
)
```

- It's a real **`UITabBarController`**, so the floating glass bar, selection morph,
  badges, VoiceOver and the long-press large content viewer are UIKit's own. Its tabs host
  empty pages that ignore touches; Flutter draws the real pages underneath.
- **Split layout:** `trailingAction` becomes a `UISearchTab`, which UIKit detaches into its
  own glass button at the trailing edge (on iOS 27 it's also set as the
  `prominentTabIdentifier`, which 27 requires for the split). By default it's a button
  (selection is vetoed and `onPressed` fires); with `selectable: true` it's a tab, reported
  as index `tabs.length`.
- Icons, titles and badges update **in place** on the existing `UITab`s. Tabs are only
  replaced when the structure changes (tab count, trailing button added or removed).
- Under Flutter popups the bar hides with UIKit's own `setTabBarHidden(_:animated:)`.

## Native icons

Everywhere an icon goes (tabs, the trailing button, `GlassShape`) takes a `NativeIcon`,
and all of them are rendered by UIKit, never rasterized by Flutter:

| | Rendered by |
|---|---|
| `NativeIcon.symbol('heart.fill')` | `UIImage(systemName:)`; tab bars apply their own symbol metrics |
| `NativeIcon.icon(Icons.add)`, `NativeIcon.icon(CupertinoIcons.gauge)` | CoreText, from the app's own copy of the icon font (found through `FontManifest.json`, package fonts included), laid out like Flutter's `Icon` |
| `NativeIcon.svgAsset('assets/x.svg')`, `NativeIcon.svg('<svg…>')` | Veneer's CoreGraphics SVG renderer |

Glyphs and SVGs come back as **template images**, so they tint like SF Symbols (tab
selection colour, glass vibrancy). Pass `tinted: false` to keep an SVG's own colours.

- **SVG coverage:** `path` (full grammar, arcs, compact numbers), `rect` (rx/ry),
  `circle`, `ellipse`, `line`, `polyline`, `polygon`, `g`; `transform`; fill, stroke, caps,
  joins, fill-rule and opacities, as attributes or in `style`, inherited through groups.
  Gradients, masks, `use`/`defs`, text and CSS stylesheets are skipped, so ship those as
  image assets instead.
- **Release builds** tree-shake icon fonts down to glyphs used by *const* `IconData`,
  exactly as for Flutter's `Icon`. Build with `--no-tree-shake-icons` if you create
  `IconData` at runtime.

## Glass groups

```dart
Stack(children: [
  ListView(/* content pills: route default group */),
  GlassGroup(zIndex: 1, child: Row(children: [/* floating controls */])),
]);
```

- Shapes merge only with shapes in the **same group**. Groups stack by `zIndex`,
  then creation order, and an upper group refracts the groups below without fusing.
- A shape outside any `GlassGroup` joins its **route's default group**, so glass on
  different routes never merges (for example, during a push). Default groups are
  created natively on first use and dropped when their last shape is gone.
- `GlassGroup.spacing` overrides `Veneer.setGlassSpacing` for that group.
- Moving a shape into another group reparents the native view: its id stays the same
  and it isn't recreated. Keep the shape's `State` alive with a `GlobalKey` if its
  parent widget type changes (see the Morph page).

## Clipping

Glass honours Flutter clips: `ClipRect`, `ClipRRect` (with per-corner radii),
`ClipOval`, and scroll viewports (`ListView`, including horizontal lists). The Clip tab
has a rounded card with a scrolling list, a capsule card with a horizontal list, and a
`ClipOval`, plus a toggle to compare with clips off.

- **Each frame**, one walk up each anchor's ancestors collects its rect, paint
  visibility and clips, using `describeApproximatePaintClip`. Rectangular clips
  intersect; the innermost rounded clip is kept exactly, and outer rounded clips
  degrade to their bounds. `ClipPath` and shaped `Container` clips count only as
  their bounding rect.
- **Clip scopes:** shapes under the same Flutter clip share one native container, whose
  wrapper view carries the mask. They can still merge with each other; shapes under
  different clips can't. A scope is keyed by the clipping *render object*, not its
  geometry, so a moving clip (a card inside a scrolling page) doesn't move shapes
  between containers.
- Clips covering the whole screen (Navigator, Overlay, full-screen lists) are ignored.
  Shapes that are fully clipped out are hidden.

## Package layout

```
lib/src/core/     veneer_bridge.dart (FFI + channel), anchor_geometry.dart, native_icon.dart
lib/src/glass/    glass_shape.dart, glass_group.dart, glass_coordinator.dart
lib/src/chrome/   native_chrome.dart
ios/veneer/Sources/veneer/
  VeneerPlugin.swift
  Core/           VeneerOverlayView.swift, NativeIcon.swift, SVGIcon.swift
  Glass/          GlassLayerView.swift, GlassShapeView.swift, ShapeClip.swift
  Chrome/         NativeTabBarHost.swift
```

## Pieces

| Dart | Native | Role |
|---|---|---|
| `NativeChromeScope` | `NativeTabBarHost` (`UITabBarController`) | Real UIKit tab bar with the split layout. Its height goes into `MediaQuery.padding` so content scrolls underneath it. |
| `NativeIcon` | `NativeIconRenderer`, `SVGIcon` | SF Symbols, IconData glyphs and SVGs rendered natively. |
| `GlassShape` | `GlassShapeView` in its group's container | A glass shape sized and positioned by Flutter layout. Its content (SF Symbol, label) is native. |
| `GlassGroup` | `GlassGroupView` | Merge scope and stacking order for the shapes below it. |
| `VeneerNavigatorObserver` | `setChromeHidden` | Fades chrome out while a Flutter popup route is showing. |
| `GlassCoordinator` | `veneer_apply_frame` (FFI) | Once per frame, packs every anchor's rect, visibility and clip into a shared buffer. |

### Per-frame geometry path

1. A persistent frame callback runs after the renderer's own, so it sees the final
   layout of the frame that was just composited.
2. It resolves each `RenderGlassAnchor`'s rect and clips in one walk up the render tree
   (`resolveAnchorGeometry`), composing transforms the way `getTransformTo(null)` does. It
   doesn't use `paint`, because scrolling moves repaint-boundary layers without
   repainting the anchor.
3. It writes the rects into a native-owned `Float64List` view (`asTypedList`, no copy),
   then makes a **synchronous, non-leaf** `dart:ffi` call.
4. Native code sets the `UIView` frames directly. They commit with the run loop's
   implicit `CATransaction`, together with Flutter's frame.

## Results so far (iPhone 17 simulator, iOS 27, debug build)

| Check | Result |
|---|---|
| Glass-vs-Flutter offset at 1200 pt/s scroll, **FFI** | median **0.17 pt** (≈ 1 px). One frame of scroll is 20 pt. |
| Same, **async method channel** | median **0.17 pt** |
| Same, **control: channel delayed 16 ms** | median **27 pt** (≈ 1.4 frames), so the harness does detect lag |
| FFI apply on main thread (merged threads) | 100%, `offMainApplies = 0` |
| Native apply cost | avg 0.07 ms, max 0.5 ms (10 shapes) |
| Cross-widget merge/morph (drag, `AnimatedPositioned`) | works |
| Groups: content pill under floating controls (`zIndex: 1`) | stacks and refracts, no fusing |
| Groups: live switch of a shape between groups | reparents, and merging stops or starts immediately |
| Groups: route default group after push and pop | dropped once empty (4 → 4) |
| Interactive glass: real `UIGlassEffect.isInteractive`, tap routed to Dart | works |
| Offstage (`IndexedStack`) / covered-route shapes hidden | works |
| Native tab bar over scrolling Flutter content; hides natively under a Flutter dialog or sheet | works |
| Split tab bar: detached trailing button, action fires without changing selection | works |
| Tab icons: SF Symbol, Material IconData + selected variant, SVG asset, Cupertino IconData + badge | all native and crisp; icon swaps update in place |
| Native XCTests (SVG grammar, arcs, transforms, styles, glyphs from bundled fonts) | 14 / 14 pass |
| Clipping: rounded card + scrolling list, capsule + horizontal list, `ClipOval` | clipped, and follows scrolling |
| Clipping: toggle clips off and on | shapes spill out and merge, then move back into their scopes |

**What this means:** on the simulator, *both* transports land in the same frame,
because with merged UI/platform threads a channel message is handled before
Core Animation commits. FFI's advantage is that it doesn't depend on task-queue
ordering and has no codec overhead. **It still has to be measured on a real device**
(ProMotion 120 Hz, release build), since simulator presentation timing isn't
representative.

## Hard-won rules (each one was a bug)

- **Never force a layout pass inside the FFI call.** An explicit top-level
  `CATransaction.commit()` or `UIView.animate` flushes window layout. That reaches
  `FlutterViewController.viewDidLayoutSubviews`, which re-enters Dart
  synchronously. Under an `isLeaf` call this **deadlocks**, and it only happens
  intermittently at cold start. `apply` only writes frames; visibility animations are
  deferred to the next main-queue turn.
- **Don't make the FFI call `isLeaf`**, for the same reason.
- **Animate `effect`, never `alpha`**, on `UIVisualEffectView`. Glass with alpha < 1
  renders incorrectly.
- **Hidden or non-interactive shapes must return `nil` from `hitTest`.** Otherwise an
  offstage page's pill shadows the button above it, and the touch falls through to Flutter.
- **Full-screen group containers must be hit-test transparent.** Each group is a
  full-screen `UIVisualEffectView`, so an upper group's content view would swallow
  touches meant for an interactive shape in a lower group.
- **Glass ignores masks on its own views.** Neither a per-shape `mask` nor one on the
  `UIGlassContainerEffect` view clips glass (the container renders its shapes together).
  A `mask` on an **ordinary `UIView` ancestor** does. Hence one wrapper per clip scope.
- **Hit-test each overlay layer separately.** The tab bar controller's full-screen (empty)
  view sits above the glass layer, so a plain `super.hitTest` returns that container and
  interactive glass stops receiving taps.
- **Attach the tab bar delegate after the initial selection, and flag programmatic
  selections.** UIKit calls the delegate synchronously for them too.
- **`IndexedStack` doesn't override `paintsChild`.** Use `Visibility.of(context)`.
- Geometry from `getTransformTo(null)` is already in logical pixels, which equal UIKit points.

## Known gaps / next decisions

- **Z-order:** all glass sits above all Flutter content. Flutter can't draw on top
  of glass, so a shape's content has to be native, and Flutter overlays need
  suppression (routes and popups are handled; an arbitrary `Overlay`/`Stack` isn't).
- **Clipping limits:** only one rounded clip per shape is exact; `ClipPath` is its bounding
  rect. Shapes under different clips can't merge. *Occlusion* isn't handled either: an
  opaque Flutter app bar painted over a list doesn't hide glass scrolling under it,
  unless the list itself clips there.
- **Chrome over pushed routes:** the tab bar is global. There's no `hidesBottomBarWhenPushed` yet.
- **Gestures:** a touch that starts on an interactive shape belongs to UIKit, so it
  can't start a Flutter scroll.
- **Accessibility:** glass is announced through Flutter `Semantics`, the tab bar through UIKit.
  Neither has been audited with VoiceOver.
- **Pre-iOS 26 fallback and non-iOS platforms:** not built.
- **Tab bar:** no sidebar/iPad adaptation or tab groups yet; the trailing button's search
  role isn't wired to real search UI.
- Not yet native: nav bar, toolbar, search, sheets and menus (present these natively),
  and a platform view for leaf controls such as `UISwitch`/`UISlider`.

## Running the example

```bash
cd example && flutter run
```

Tabs: **Sync** (the lag test; ▶ auto-scrolls, 📏 switches to measure mode), **Morph**
(drag the loose drop into the cluster, Split/Join, Shared/Own group), **Clip** (Flutter
clips on native glass), **Diagnostics** (transport A/B, native stats, dialog/sheet/route
edge cases).

### Measuring sync lag

```bash
xcrun simctl launch --terminate-running-process <udid> dev.veneer.example -VENEER_TRANSPORT ffi -VENEER_MEASURE 1
```

```bash
python3 tool/measure_sync.py <udid> 20
```

`-VENEER_TRANSPORT` accepts `ffi`, `channel` or `delayedChannel`. Always run
`delayedChannel` too, as the control.

## License

MIT, see [LICENSE](LICENSE).
