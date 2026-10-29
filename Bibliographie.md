# Bibliographie — SVGroom

Everything SVGroom draws on: concepts, specifications, frameworks. There is **no third‑party code or library**; the app uses only Apple system frameworks.

## Inspiration & concepts

| Source | What was used | Link |
|---|---|---|
| Adobe Lightroom Classic — Library module | Workflow concept only: catalog, folders panel, grid / loupe, stars, pick/reject flags, color labels, "find missing photos", keyboard culling (0–5, P, X, U, 6–9, G, E, auto‑advance) | https://helpx.adobe.com/lightroom-classic/help/keyboard-shortcuts.html · https://helpx.adobe.com/lightroom-classic/help/locate-missing-photos.html |
| Inkscape layers convention | Layers are `<g inkscape:groupmode="layer" inkscape:label="…">`; hidden = `style="display:none"` | https://inkscape.org/doc/inkscape-man.html · https://wiki.inkscape.org/wiki/Inkscape_SVG_vs._plain_SVG |
| AxiDraw / pen‑plotter practice | Idea of per‑layer plotting (one pen per layer), pen‑up vs pen‑down speed, pen‑lift cost in time estimates | https://axidraw.com/doc/cli_api/#options-general · https://wiki.evilmadscientist.com/AxiDraw |
| vpype | Common plotter SVG output (layers as groups with a stroke colour), and length / pen-up stats as a concept | https://github.com/abey79/vpype · https://vpype.readthedocs.io/ |

## Specifications

| Spec | Used for | Link |
|---|---|---|
| SVG 1.1 — Paths | Path data grammar (M L H V C S Q T A Z, implicit commands, compact numbers and flags) | https://www.w3.org/TR/SVG11/paths.html |
| SVG 1.1 — Implementation notes F.6.5 | Arc endpoint → centre parameterisation | https://www.w3.org/TR/SVG11/implnote.html#ArcConversionEndpointToCenter |
| SVG 1.1 — Coordinate systems | `viewBox`, `preserveAspectRatio` (xMidYMid meet), `transform` list | https://www.w3.org/TR/SVG11/coords.html |
| CSS units | mm, cm, in, pt, pc, Q, px (96 px = 1 in) | https://www.w3.org/TR/css-values-3/#absolute-lengths |
| ISO 216 / ANSI paper sizes | A0–A6, B3–B5, Letter, Legal, Tabloid detection | https://en.wikipedia.org/wiki/ISO_216 · https://en.wikipedia.org/wiki/Paper_size#North_American_paper_sizes |

## Apple frameworks (system, ship with macOS)

| Framework | Role | Docs |
|---|---|---|
| SwiftUI | Whole UI: split view, inspector, lazy grid, key handling | https://developer.apple.com/documentation/swiftui |
| AppKit | NSScrollView magnification (loupe), panels, NSWorkspace (Trash, Finder, Open With) | https://developer.apple.com/documentation/appkit |
| QuickLookThumbnailing | Grid thumbnails (WebKit rendering, system cache) | https://developer.apple.com/documentation/quicklookthumbnailing |
| NSImage SVG support (CoreSVG) | Vector preview in the loupe | https://developer.apple.com/documentation/appkit/nsimage |
| Foundation `XMLParser` / `XMLDocument` | Streaming analysis; hidden-layer stripping for the preview | https://developer.apple.com/documentation/foundation/xmlparser |
| URL bookmarks | Following moved / renamed files and folders | https://developer.apple.com/documentation/foundation/url/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:) |
| CryptoKit (SHA‑256) | Content fingerprint for relinking | https://developer.apple.com/documentation/cryptokit |
| Swift Testing | Unit tests of the analyzer | https://developer.apple.com/documentation/testing |
| CoreGraphics + `iconutil` | App icon, drawn in code by `scripts/make-icon.swift` (original artwork: plotted waves on a sheet, rating star) | https://developer.apple.com/design/human-interface-guidelines/app-icons |

## Commercial use

**Score: 3 — No problem for commercial use.**

- Code and app icon: written / drawn for this project; only Apple system frameworks, used as intended under the Xcode / Apple Developer agreements. No open-source dependency, so no licence obligations.
- Specifications (W3C, ISO) are implemented, not copied; implementing them is free.
- Lightroom, Inkscape, AxiDraw and vpype are cited as *inspiration only*; no code, assets or trade dress are reused. Don't use "Lightroom" in the product name or marketing.
- Not checked: whether "SVGroom" is a registered trademark. Check before you sell the app.
- Selling outside the Mac App Store requires signing with a Developer ID and notarisation (the current build uses an ad-hoc signature).

## Credits

```
SVGroom — an SVG library and culling tool for pen-plotter work.
Design & direction: Tonino Rizzo (Toninosaurus).
Built with Apple SwiftUI, AppKit, QuickLookThumbnailing and CryptoKit.
Implements the W3C SVG 1.1 path and arc algorithms.
Workflow inspired by Adobe Lightroom Classic's Library module; layer conventions from Inkscape.
Developed with the assistance of Claude (Anthropic).
```
