# Wander — the Veneer example

A travel journal that uses every Veneer component, with Liquid Glass over photos so you can see it
work.

```bash
flutter run
```

| Where | What it shows |
|---|---|
| **Explore** tab | The native navigation bar with a leading title and grouped buttons (Search, a profile menu); featured places on `GlassBackground` cards; a `GlassSegmentBar` that pins under the navigation bar while the photos scroll beneath it; a grid with `GlassShape` labels and `NativeContextMenu`s |
| **Search** (Explore) | `NativeSearchToolbar`: the system search bar at the bottom of the screen, over Flutter results |
| **Place** page | A photo running under the navigation bar's glass buttons; a `NativeSegmentedControl`; floating glass buttons in a `GlassGroup` — one opens a native menu of trips, the other the stay sheet; banners from `showNativeBanner` |
| **Book a stay** sheet | A real UIKit sheet (`staySheet` entrypoint in `lib/main.dart`, the place passed as its payload): `NativeSegmentedControl`, `NativeMenuAnchor`, `NativeSlider`, `NativeSwitch` and `showNativeAlert` |
| **Trips** tab | A list that pushes each trip on a phone; on a wide screen (the unfolded iPhone Duo, iPhone landscape) two `NativeChromePane`s side by side, each with its own navigation bar |
| **Journal** tab | A capsule title with an image, and `NativeComposer` with a `+` menu, toolbar, mentions and voice notes |
| **Components** tab | Each component on its own; pages for merging glass, clipped glass and the **Lab** (icon types, the glass sync-lag test, native stats); the **Flutter replicas** switch |
| **Assistant** (tab bar's trailing button) | A trip planner in a native sheet (`assistantSheet` entrypoint): `NativePromptComposer` with attachments, dictation and voice mode |

Launch arguments (iOS):

- `-VENEER_FALLBACK 1` — start with the Android / iOS 15–25 UI on iOS 26 (or use the **Flutter
  replicas** switch on the Components tab).
- `-VENEER_TRANSPORT ffi|channel|delayedChannel` and `-VENEER_MEASURE 1` — for
  `tool/measure_sync.py` (see [doc/architecture.md](../doc/architecture.md)).

## Icons

The app's icons are [Phosphor Icons](https://phosphoricons.com) (MIT, see
`assets/fonts/LICENSE-phosphor.txt`), compiled into the `AppIcons` font. To add icons, list
them in `tool/icon_font/icons.txt` and rebuild:

```bash
pip install fonttools
npm pack @phosphor-icons/core && tar xzf phosphor-icons-core-*.tgz
python3 tool/icon_font/build_icon_font.py package/assets
```

This writes `assets/fonts/AppIcons.ttf` and `lib/app_icons.dart`. Each icon is a glyph on a
square em with its SVG's padding, so every icon has the same size and optical alignment.

## Photos

The photos are from [Unsplash](https://unsplash.com), used under the
[Unsplash License](https://unsplash.com/license). Thanks to their photographers:

| Photo | By |
|---|---|
| `lisbon.jpg` | [@juliandik](https://unsplash.com/@juliandik) |
| `lisbon_2.jpg` | [@malyushev](https://unsplash.com/@malyushev) |
| `santorini.jpg` | [@shotsbytania](https://unsplash.com/@shotsbytania) |
| `santorini_2.jpg` | [@zombience](https://unsplash.com/@zombience) |
| `kyoto.jpg` | [@kotoku91](https://unsplash.com/@kotoku91) |
| `kyoto_2.jpg` | [@magicetea](https://unsplash.com/@magicetea) |
| `iceland.jpg` | [@deko_photo4](https://unsplash.com/@deko_photo4) |
| `iceland_2.jpg` | [@robertbye](https://unsplash.com/@robertbye) |
| `moraine.jpg` | [@andyjh07](https://unsplash.com/@andyjh07) |
| `positano.jpg` | [@floklassen](https://unsplash.com/@floklassen) |
| `positano_2.jpg` | [@louisekrause](https://unsplash.com/@louisekrause) |
| `marrakech.jpg` | [@zakariaedaoui](https://unsplash.com/@zakariaedaoui) |
| `bali.jpg` | [@killpeopleinyourmind](https://unsplash.com/@killpeopleinyourmind) |
| `patagonia.jpg` | [@samuelqyx](https://unsplash.com/@samuelqyx) |
| `tokyo.jpg` | [@erikeae](https://unsplash.com/@erikeae) |
| `sahara.jpg` | [@ashley_hayes](https://unsplash.com/@ashley_hayes) |
| `maldives.jpg` | [@seefromthesky](https://unsplash.com/@seefromthesky) |
| `maldives_2.jpg` | [@moseshalym](https://unsplash.com/@moseshalym) |
