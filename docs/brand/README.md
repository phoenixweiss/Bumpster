# Bumpster brand assets

Bumpster has two identity forms: **Flat** for graphical surfaces and
**Terminal** for monospace text environments. Both use the same release-counter
idea: `X.Y.Z`, with a caret above `Z` marking the version bump.

## Core assets

| Asset | Use |
| --- | --- |
| `bumpster-mark.svg` | Standalone Flat mark |
| `bumpster-lockup.svg` | Primary Flat mark and wordmark |
| `bumpster-favicon.svg` | Small browser icon; an optical crop of the bumped `Z` cell |
| `bumpster-app-icon.svg` | Full-bleed, mask-safe application icon source |
| `bumpster-social-card.svg` | 1200 × 630 social preview source |
| `bumpster-flat-terminal-sheet.svg` | Flat and Terminal reference sheet |
| `bumpster-favicon-sheet.svg` | Favicon construction and size reference |

PNG companions are included for tools and surfaces that cannot consume SVG.
The SVG lockup uses an outlined IBM Plex Mono Bold wordmark and has no runtime
font dependency.

## Terminal form

```text
+---+ +---+ +-^-+
| X |.| Y |.| Z |  BUMPSTER
+---+ +---+ +---+
```

The Terminal form is printable 7-bit ASCII, three lines high, and 27 columns
wide. Keep its spacing unchanged. Interactive color output highlights both the
caret and `Z`; redirected output, `NO_COLOR`, and `TERM=dumb` stay plain.

## Palette

| Role | Hex |
| --- | --- |
| Bump burgundy | `#941E3D` |
| Signal rose | `#D85A78` |
| Warm accent | `#E7A06C` |
| Paper | `#F3F0EA` |
| Ink | `#171717` |
| Muted neutral | `#706A64` |

Use the full Flat mark or lockup whenever space permits. At favicon sizes, use
the supplied bumped-`Z` crop instead of shrinking the full three-cell mark.
