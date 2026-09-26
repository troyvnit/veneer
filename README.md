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
      ├─ UIScrollView (clear)      ← hosts iOS 26's scroll edge effect over Flutter content
      ├─ UITabBarController.view   ← native chrome: a real tab bar controller (child of
      │                              the FlutterViewController) with empty, touch-transparent tabs
      ├─ UINavigationBar           ← native bar: glass back button, title capsule, trailing group
      └─ NativeComposerView        ← native composer: glass capsule ⇄ card, keyboard-synced
```

Glass samples whatever is composited beneath it, so it refracts Flutter
pixels. Shapes in the same group share one container, so separate widgets **merge and
morph** into each other. That can't happen when each widget is its own platform view.

## Platform support

| | What renders |
|---|---|
| **iOS 26+** | The native layer: UIKit chrome, Liquid Glass, scroll edge effects, the native composer |
| **Android, iOS 15–25** | **Flutter replicas** of the same UI, with the same layout, sizes, positions, colours and corner radii as the iOS 26 chrome, on solid surfaces instead of glass |

- **One widget tree for every platform.** The package installs on **iOS 15+** and Android;
  `Veneer.isSupported` is true only on iOS 26+, and every widget picks its path itself.
  There's no `if (Platform.isIOS)` in app code.
- **Replica geometry** comes from the native metrics:
  - **Tab bar:** a floating 61 pt capsule with 20 pt margins, a pill behind the selected item,
    and a 61 pt trailing circle 8 pt away. Off iOS the trailing button behaves as a create-style
    action.
  - **Top bar:** a 44 pt back circle 16 pt from the edge, then the title capsule, then the trailing
    group sharing one capsule. A fade stands in for the edge blur.
  - **Composer:** the 44 pt capsule 9 pt above the tab bar, morphing into the 104 pt card 9 pt above
    the keyboard. Its bottom follows Flutter's keyboard inset, and it expands only while the
    keyboard is up, so Android's back key collapses it.
  - **Glass shapes:** solid surfaces in the same shape, with a press swell. They don't merge.
- **Colours** are iOS system values (`label`, `secondaryLabel`, `placeholderText`, `systemBlue`,
  `systemRed`), with white or #2C2C2E surfaces, a hairline border and a soft shadow. They follow
  light and dark mode.
- **Icons:** IconData renders with `Icon`, SVGs with `flutter_svg`, and common SF Symbol names map
  to Material icons (`NativeIcon.symbol(name, fallback: …)` covers the rest).
- **Preview the replicas on iOS 26** with `Veneer.debugForceFallback = true` before `runApp`
  (the example: `-VENEER_FALLBACK 1`).
- **Web isn't supported** (the bridge uses `dart:ffi`).

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

- **At most 5 items**, counting the trailing button: that's all `UITabBarController` shows on
  iPhone before collapsing the rest into a "More" tab (and dropping the split button), so
  `NativeChromeScope` asserts on it.
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

## Native navigation bar and scroll edge effect

```dart
NativeNavigationBar(
  leading: NativeBarButton(icon: NativeIcon.symbol('chevron.left'), title: 'Back', onPressed: pop),
  title: NativeBarTitle(title: 'launch-crew', subtitle: '6 members', icon: NativeIcon.symbol('lock.fill'), capsule: true),
  trailing: [
    NativeBarButton(icon: NativeIcon.svgAsset('assets/icons/app_mark.svg', tinted: false), title: 'Apps'),
    NativeBarButton(icon: NativeIcon.symbol('headphones'), title: 'Huddle'),
  ],
  child: pageBody,
)
```

- It's a real **`UINavigationBar`**, so on iOS 26 the items are Liquid Glass with the system
  metrics: 44 pt circles and capsules, and adjacent trailing items sharing one capsule. With
  `capsule: true` the title is a tappable glass capsule holding an icon, title and subtitle,
  like a chat app's channel header; otherwise it's the system's title and subtitle.
- It **wraps the page** (`child`), under a `NativeChromeScope`. It shows while that page is
  visible (hidden on other `IndexedStack` tabs and under pushed routes), and its height goes
  into `MediaQuery` top padding, so content starts below it and scrolls under it.
- **Scroll edge effect:** content scrolling under the bar dissolves into iOS 26's *own*
  soft edge effect, not an imitation. A transparent, non-interactive `UIScrollView` in the
  overlay hosts it, and the bar registers through `UIScrollEdgeElementContainerInteraction`,
  so the effect is shaped around the bar's controls exactly as on a UIKit screen. The same
  applies at the bottom (`NativeChromeScope(scrollEdgeEffect:)`), shaped around the tab bar and
  the composer.

## Native composer

```dart
NativeComposer(
  controller: composer,
  placeholder: 'Message launch-crew',
  leading: NativeComposerButton(icon: NativeIcon.symbol('plus'), title: 'Attach', onPressed: attach),
  idleAction: NativeComposerButton(icon: NativeIcon.symbol('mic'), title: 'Voice clip'),
  toolbar: [
    NativeComposerButton(icon: NativeIcon.symbol('textformat'), title: 'Formatting'),
    NativeComposerButton(icon: NativeIcon.symbol('face.smiling'), title: 'Emoji'),
    NativeComposerButton(icon: NativeIcon.symbol('at'), title: 'Mention'),
    NativeComposerButton(icon: NativeIcon.svgAsset('assets/icons/slash_command.svg'), title: 'Shortcuts'),
  ],
  tintColor: Color(0xFF2BAC76),
  onSend: send,
  child: ListView(reverse: true, ...),
)
```

Put it in a `Scaffold(resizeToAvoidBottomInset: false)`: it handles the keyboard itself, on
both the native and the replica path.

- **Everything is UIKit**, including the text view, the glass (`UIGlassEffect`, and
  `UIButton.Configuration.glass()` for the + circle) and the toolbar buttons.
- **Idle:** a 44 pt glass capsule 9 pt above the tab bar, aligned with its edges:
  `(+) placeholder … 🎙`.
- **Focused:** it morphs into a card 8 pt from the screen edges and 9 pt above the keyboard,
  with the text on top and the toolbar row `(+) Aa ☺ @ /  …  ➤` below. The morph runs **inside
  the keyboard's own animation** (its duration and curve from the keyboard notification),
  so the card and keyboard move as one. A hardware keyboard falls back to a spring.
- **Text:** grows to `maxLines`, then scrolls. Send enables and tints when there's text, and
  `clearOnSend` clears natively.
- **Flutter content:** `child` gets bottom padding for the space the composer takes above the
  keyboard or tab bar (animated with the morph), and the keyboard inset is consumed so an
  inner `Scaffold` doesn't also resize.
- **Interactive keyboard dismissal** (`interactiveKeyboardDismissal`, on by default): dragging
  the Flutter content down pulls the keyboard with the finger, with the composer riding on
  it, and releasing dismisses it or snaps it back. It's UIKit's own mechanism. An invisible
  `UIScrollView` with `keyboardDismissMode = .interactive` has its pan gesture attached to the
  `FlutterView` (`cancelsTouchesInView = false`, so Flutter still scrolls), and the composer
  follows `keyboardLayoutGuide`, which UIKit updates frame by frame during the drag. Only
  vertical drags that start on Flutter content count.
- **Controller:** `NativeComposerController` exposes the text and focus, plus
  `focus()`/`unfocus()`/`clear()`; call `unfocus()` from taps on the content to dismiss the keyboard.
- **Metrics** were measured from Slack's iOS composer: 36 pt + circle, toolbar glyphs about
  19 pt spaced 41 pt apart, send 25 pt from the trailing edge, and a 28 pt maximum corner radius.

The example's **Chat** tab puts it all together: native bar, scroll edge effect, Flutter-drawn
messages, the composer and the split tab bar.

## Native icons

Everywhere an icon goes (tabs and their selected icons, the trailing button, `GlassShape`)
takes a `NativeIcon`. All of them are rendered by UIKit, CoreText and CoreGraphics,
never rasterized by Flutter:

| | |
|---|---|
| `NativeIcon.symbol('heart.fill')` | SF Symbol. Tab bars apply their own symbol metrics; glass follows Dynamic Type unless `iconSize` is set |
| `NativeIcon.icon(Icons.add)` | Any `IconData`: Material, Cupertino, package or custom icon fonts, read from the app's own copy of the font via `FontManifest.json` and laid out like Flutter's `Icon` |
| `NativeIcon.icon(Symbols.home, fill: 1, weight: 600, grade: 0, opticalSize: 24)` | Variable icon fonts (Material Symbols) through CoreText font variations |
| `NativeIcon.svgAsset('assets/x.svg')`, `.svgFile(path)`, `.svg('<svg…>')` | Veneer's native SVG renderer, from an asset (packages too), a file on disk, or markup |

**IconData:** `fontFamilyFallback` is tried in order, and `matchTextDirection` icons are
mirrored by UIKit in right-to-left layouts. Release builds tree-shake icon fonts down to
glyphs used by *const* `IconData`, exactly as for `Icon`; build with `--no-tree-shake-icons`
if you create `IconData` at runtime.

**SVG** covers:
- **Structure:** nested `svg` viewports, `g`, `a`, `switch`, `defs`, `symbol`, `use`
  (`href`/`xlink:href`).
- **Shapes:** `path` (full grammar including arcs), `rect`, `circle`, `ellipse`, `line`,
  `polyline`, `polygon`; `text`/`tspan` via CoreText (font family, weight, style, size,
  anchor, dx/dy); `image` from `data:` URIs (PNG, JPEG or nested SVG).
- **Paint:** hex, `rgb()`, `hsl()`, the 148 CSS colour names, `currentColor`; linear and radial
  gradients with units, `gradientTransform`, `href` inheritance and pad/reflect/repeat; fill
  and stroke opacity, rules, caps, joins, miter limit, dashes.
- **Compositing:** group `opacity` (flattened, like browsers), `clip-path`, luminance `mask`,
  `display`, `visibility`, `overflow`.
- **Styling:** presentation attributes, `<style>` CSS (type, class, id and universal
  selectors, compound and descendant selectors, specificity, `@media` bodies), inline
  `style`, inheritance, `inherit`.
- **Layout:** `viewBox`, `preserveAspectRatio` (all alignments; meet, slice or none), and
  units px, pt, pc, in, cm, mm, em, ex and %.

Filters, patterns (their fallback colour is used), markers, `textPath`, `foreignObject`,
animation and external `href`s aren't rendered.

**Tinting:** glyphs and SVGs are template images by default, so they tint like SF Symbols
(tab selection colour, glass vibrancy, dark mode). `tinted: false` keeps an SVG's own
colours; it gets light and dark variants, so `currentColor` follows the interface style.

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
lib/src/chrome/   native_chrome.dart, native_navigation_bar.dart, native_composer.dart
ios/veneer/Sources/veneer/
  VeneerPlugin.swift
  Core/           VeneerOverlayView.swift, NativeIcon.swift, SVGIcon.swift (document + renderer),
                  SVGPathParser.swift, SVGValues.swift
  Glass/          GlassLayerView.swift, GlassShapeView.swift, ShapeClip.swift
  Chrome/         NativeTabBarHost.swift, NativeNavigationBarHost.swift, NativeComposerView.swift,
                  ScrollEdgeEffectHost.swift, KeyboardDismissProxy.swift
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
| Native navigation bar: glass back button, title capsule, grouped trailing capsule | matches Slack's layout |
| Scroll edge effect over Flutter content (system `UIScrollEdgeEffect`) | content blurs progressively under the bar |
| Composer: idle capsule → focused card over the keyboard → idle | about 0.4 s each way, continuous and keyboard-synced (checked frame by frame in a recording) |
| Composer typing, growth, send, clear; list taps dismiss the keyboard | works |
| Interactive dismissal: keyboard and composer follow the finger, then dismiss or snap back | works (checked frame by frame, with Flutter scrolling the same drag) |
| Native XCTests: SVG rendering (CSS, use/symbol, gradients, clip/mask, group opacity, dashes, viewports, text, images); IconData fonts, fallbacks, mirroring, variable axes; dark-mode SVG | 28 / 28 pass |
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
- **Check the composer's frame before hit-testing it.** While its text view is first
  responder, UIKit resolves hits on it to text-interaction views even for points far outside
  it, which steals every tap from Flutter (and pops up AutoFill).
- **Only send chrome config when it changes.** Pages rebuild every frame while the keyboard
  animates (`MediaQuery` changes); callbacks are refreshed locally instead.
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
- **Composer:** no attachment previews or rich text. During an interactive drag, Flutter
  content keeps the keyboard-up padding until release (then it animates normally).
- **Tab bar:** no sidebar/iPad adaptation or tab groups yet; the trailing button's search
  role isn't wired to real search UI.
- Not yet native: nav bar, toolbar, search, sheets and menus (present these natively),
  and a platform view for leaf controls such as `UISwitch`/`UISlider`.

## Running the example

```bash
cd example && flutter run
```

It runs on iOS 26 (native), on Android and iOS 15–25 (replicas), and on iOS 26 with
`-VENEER_FALLBACK 1` to compare the two on one device.

Tabs: **Chat** (Slack-style channel: native bar, edge effect, composer), **Morph**
(drag the loose drop into the cluster, Split/Join, Shared/Own group), **Clip** (Flutter
clips on native glass), **Lab** (the sync lag test, transport A/B, native stats, icon
showcase, dialog/sheet/route edge cases).

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
