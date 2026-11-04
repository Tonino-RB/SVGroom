# SVGroom

A Lightroom-style library for SVG files, made for pen-plotter work. Native macOS app (SwiftUI, Apple silicon, macOS 14+).

- **Catalog**: one `.svgroom` file, stored wherever you choose (File › New Catalog…). It holds ratings, flags, color labels, file locations and cached analysis.
- **Folders**: File › Add Folder… (⇧⌘I), or drag folders onto the sidebar. Subfolders are included.
- **Culling**: stars, pick/reject flags, color labels, a size (XS, S, M, L, XL — one per file) and custom tags (several per file; add them in the inspector, rename, reorder or delete them in Manage Tags…); filter by rating, flag, label, size, tag, paper format and name.
- **Linked folders**: right-click a folder › Link With… to pick folders with the same structure (e.g. one export at several settings). A rating, flag or label set on a file is also set on the file at the same relative path in every linked folder. Right-click › Sync Tags… for files tagged before the link: untagged files take the tags of their linked versions, and files tagged differently are listed with previews to choose which version to copy (one by one or for all), or leave untouched. Right-click › Unlink to stop. **Versions** (toolbar) shows the selected file next to the same file in every linked folder, at the same scale, with plot time, pen-down distance and pen lifts; the Simulate button shows them through the simulation settings instead. Click a version to select it (click again to deselect): the inspector, rating keys, menus and Trash then act on that version alone, without changing its linked versions.
- **Plotter info**: size in mm, paper format (A0–A6, B3–B5, Letter, Legal, Tabloid), Inkscape layers with pen colour, estimated plot time, pen-down / pen-up distances, pen lifts, margins, and warnings (off-page content, text, bitmaps).
- **Layers**: the eye toggles in the inspector hide or show layers in the preview and in the time estimate. The file itself is never modified.
- **Simulation / Compare** (toolbar: Normal · Simulation · Compare): preview the selected file on another sheet (A0–A6, B3–B5, Letter… or custom mm, portrait/landscape), with the drawing scaled to a given longest side and centred, a pen width in mm, and an ink colour per layer. Shapes are drawn as plotted: strokes only, round pen tips. Compare shows the original and the simulation side by side at the same scale. Settings are kept between files; the file itself is never modified. G, E, Space or Esc go back to Normal.
- **Broken links**: moved or renamed files are found again (bookmarks, then name + size). After File › Synchronize Folders (⌘R) or right-click › Synchronize, files and folders still missing are listed: Locate… the ones that were moved, Remove the ones that were deleted. Folders that can't be found show in red: right-click › Locate Folder…. Missing files are listed under *Missing Files*, with Locate… and File › Find Missing Files in Folder… (matches by name + size, then by content hash).
- **Copy to Folder…** (SVG menu, right-click, or the inspector with several files selected; ⇧⌘E) copies the selected files into one folder, e.g. a new project. Each copy is named after its folder (`coral/a.svg` → `coral_a.svg`), with more parent folders when needed to keep names apart (`f1/coral/a.svg` → `f1_coral_a.svg`); names already in the folder get a number. The originals are not changed.
- **Drag out**: drag a thumbnail (or the loupe / a version's sheet) to the Finder or another app to copy the file; dragging inside the selection carries every selected file.
- **Delete** moves files to the Trash after a confirmation. Right-click a sidebar folder › Move Folder to Trash… moves the whole folder (all its files and subfolders) to the Trash and forgets its files.
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
| ⇧⌘E | Copy to folder… |

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
