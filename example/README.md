# Veneer example

A small messaging app that exercises every Veneer component.

```bash
flutter run
```

| Where | What it shows |
|---|---|
| **Chat** tab | Native tab bar and navigation bar, the scroll edge effect over Flutter messages, and the messaging composer with interactive keyboard dismissal |
| **AI button** (tab bar) | An assistant in a real UIKit sheet (`assistantSheet` entrypoint in `lib/main.dart`): native navigation bar and menus, the prompt composer with attachments and voice mode |
| **Morph** tab | Glass shapes merging and splitting within groups |
| **Clip** tab | Glass inside Flutter clips and scrolling lists |
| **Lab** tab | Icon types (SF Symbol, IconData, SVG), the glass sync-lag test and native stats |

Launch arguments (iOS):

- `-VENEER_FALLBACK 1` — show the Android / iOS 15–25 UI on iOS 26.
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
