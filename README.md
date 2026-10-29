# SVGroom

A Lightroom-style library for SVG files, made for pen-plotter work. Native macOS app (SwiftUI, Apple silicon, macOS 14+).

- **Catalog**: one `.svgroom` file, stored wherever you choose (File › New Catalog…). It holds ratings, flags, color labels, file locations and cached analysis.
- **Folders**: File › Add Folder… (⇧⌘I), or drag folders onto the sidebar. Subfolders are included.
- **Culling**: stars, pick/reject flags, color labels; filter by rating, flag, label, paper format and name.
- **Plotter info**: size in mm, paper format (A0–A6, B3–B5, Letter, Legal, Tabloid), Inkscape layers with pen colour, estimated plot time, pen-down / pen-up distances, pen lifts, margins, and warnings (off-page content, text, bitmaps).
- **Layers**: the eye toggles in the inspector hide or show layers in the preview and in the time estimate. The file itself is never modified.
- **Broken links**: moved or renamed files are found again (bookmarks, then name + size). Folders that can't be found show in red: right-click › Locate Folder…. Missing files are listed under *Missing Files*, with Locate… and File › Find Missing Files in Folder… (matches by name + size, then by content hash).
- **Delete** moves files to the Trash after a confirmation.
- Analysis runs in the background and is cached, so browsing stays fast. OneDrive online-only files are not downloaded until you select them.

## Keyboard (grid & loupe)

| Key | Action |
|---|---|
| ← → ↑ ↓ | Move selection |
| 0–5 | Rating |
| P / X / U | Pick / Reject / Unflag |
| 6 7 8 9 | Red / Yellow / Green / Blue label (toggle) |
| G / E, Space, Return | Grid / Loupe |
| Z | Zoom toggle in loupe (or pinch) |
| ⌫ or ⌘⌫ | Move to Trash… |
| ⌘A | Select all |
| ⌘R | Synchronize folders |
| ⇧⌘R / ⌘E | Reveal in Finder / Open in default app |

SVG › Auto Advance After Rating jumps to the next file after each key (fast culling).

## Plot time

Modelled on an AxiDraw (high-resolution mode, standard pen-lift servo) and checked against the AxiDraw software's own estimate (v3.9.5, preview mode): within 0.5 % on test patterns and about 1 % on real exports. It accounts for acceleration, slowing down in corners, how the AxiDraw plans very short moves, paths that touch being drawn in one go, and the servo time of each pen lift. Paths are plotted in file order (AxiDraw reordering off). Each layer is timed as its own job, starting and ending at the home corner.

Settings (⌘,) take the same values as AxiDraw Control. Defaults: pen-down speed 20 %, pen-up 75 %, acceleration 50 %, pen up / down position 60 / 30 %, raising 100 %, lowering 50 %. Changing them recomputes the times in the background.

## Build

```bash
./scripts/build-app.sh      # → dist/SVGroom.app (arm64, release, ad-hoc signed)
swift test --scratch-path ~/Library/Caches/SVGroom-build
swift scripts/make-icon.swift  # redraws Resources/AppIcon.icns
```

Build products go to `~/Library/Caches/SVGroom-build` so OneDrive doesn't sync them. `open Package.swift` opens the project in Xcode.

Sources and licensing: see [Bibliographie.md](Bibliographie.md).
