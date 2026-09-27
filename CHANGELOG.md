# Changelog

## 0.2.1

- **Sheets:** `NativeSheetDetent.content()` sizes a Flutter-drawn sheet to its content and
  follows it as it changes; sheets shorter than large float inset from the screen edges. Sheet
  content gets a `Material` (text fields and list tiles work as-is) and the sheet's surface as
  its scaffold background.
- **Sheets, safe area and keyboard:** a sheet rising for the keyboard grows at least as fast as
  the keyboard, so its content is never squeezed between the two; the keyboard inset reaching
  the content no longer counts the sheet's floating inset twice; dragging the sheet puts the
  keyboard away.
- **Fixes:** bars, composers and the tab bar come back when a popup or sheet on an outer
  navigator closes (a page in a tab's navigator); after a hot restart the native overlay
  reports its insets again, so pages under a `NativeNavigationBar` don't slide under the bar.

## 0.2.0

- **Navigation bar:** titles can be leading-aligned (`NativeBarTitle.alignment`) and styled
  with your app's fonts and colours (`style`, `subtitleStyle`), natively too. The title capsule
  takes an `accessory` glyph.
- **Bar buttons:** `badge`, `prominent` tinted glass, text-only buttons, and `group` to split
  trailing buttons into separate capsules.
- **Menus:** `NativeMenuItem.divider()` for sections.
- **Prompt composer:** `stopAction`, `sendEnabled`, `sendBusy` and `editable`; attachments
  take `loading`.
- **Sheets:** `payload` / `NativeSheet.payload()` pass data into pre-warmed engines. Sheet
  engines no longer restyle the app's status bar, and each is torn down when its sheet is
  dismissed (their overlays no longer outlive them).
- **Fallbacks:** `VeneerFallbackStyle` is a `ThemeExtension`, so replicas can follow your
  design system. The replica bar spans its parent and places titles like UIKit, the menu is
  opaque with section bands, the tab bar sizes to its tabs and clears Android's gesture handle,
  and the Flutter sheet has a rim at its edge.
- **Fixes:** a bar or composer on a page inside a nested navigator (a tab's) now hides when an
  outer route covers it; a `NativeNavigationBar` outside a `NativeChromeScope` gives its content
  the right top inset; a composer host rebuilt mid-page keeps its height.

## 0.1.1

- **Composer:** if the software keyboard goes away while the text view keeps
  focus (for example at the end of an interactive dismissal), the composer
  now drops focus and collapses to its capsule, instead of staying expanded
  with no keyboard and bringing the keyboard back on the next tap.
- **Composer:** the collapsed capsule always shows its text from the start.
- **Docs:** a demo of the example app in the README.

## 0.1.0

First public release.

- **Tab bar** (`NativeChromeScope`): a real `UITabBarController` with the split layout's
  trailing button, badges, selected icons and a bottom scroll edge effect. Slides away while
  another route covers its page.
- **Navigation bar** (`NativeNavigationBar`): a real `UINavigationBar` with glass buttons, a
  title capsule, grouped trailing buttons, native menus, animated item changes and iOS 26's
  scroll edge effect over Flutter content.
- **Composer** (`NativeComposer`): a messaging composer that morphs from a capsule into a card
  above the keyboard inside the keyboard's animation, with interactive keyboard dismissal.
- **Prompt composer** (`NativePromptComposer`): an assistant-style composer with inline
  actions, a primary action that becomes send, multi-line growth, attachments and glass side
  actions that split off for a live session.
- **Sheets** (`showNativeSheet`): real UIKit sheets hosting Flutter content in a pre-warmed
  engine, with detents, grabber and Veneer's bars and composers inside; a Flutter sheet with the
  same behaviour elsewhere.
- **Menus** (`NativeMenuItem`): native `UIMenu`s from bar buttons, composer buttons and glass
  shapes.
- **Glass** (`GlassShape`, `GlassGroup`): Liquid Glass positioned by Flutter layout every frame
  through a synchronous `dart:ffi` call, merging within groups and clipped by Flutter clips.
- **Icons** (`NativeIcon`): SF Symbols, `IconData` from any icon font (including variable
  fonts), a native SVG renderer and raster images.
- **Flutter replicas** of every component for Android and iOS 15–25, and
  `VeneerFallbackScope` / `Veneer.debugForceFallback` to force them.
