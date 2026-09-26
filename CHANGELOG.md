# Changelog

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
