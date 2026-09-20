# Connect IQ Store assets

The two PNGs use the same black radiation-trefoil geometry and solid yellow
background. They contain no text, transparency, Garmin marks or third-party
wordmarks or logos.

| File | Purpose | Dimensions |
| --- | --- | ---: |
| `store-icon.png` | Connect IQ Store listing icon | 500 × 500 px |
| `on-device-store-icon.png` | Connect IQ on-device store icon | 128 × 128 px |

Distinct 500 × 500 RGB cover images for each Store identity are under
`covers/`:

| File | Store identity |
| --- | --- |
| `covers/cover-app-production.png` | RadMonitor production watch app |
| `covers/cover-app-beta.png` | RadMonitor Beta watch app |
| `covers/cover-field-production.png` | RadMonitor Field production data field |
| `covers/cover-field-beta.png` | RadMonitor Field Beta data field |

The production watch-app cover shows a schematic Instinct 3 Solar Tactical-style
chassis with the one-hour plot and a trefoil in its circular window. The
production field cover combines dual history plots with a dotted schematic
route. Production covers use restrained color; each beta cover is a monochrome
derivative of the matching composition and adds `BETA` only as black typography
on a white clip beside the product name. All four covers are opaque 500 × 500
8-bit RGB PNGs kept below the Connect IQ submission limit of 300 KB.

Editable sources are `store-icon.svg` and `on-device-store-icon.svg`. Regenerate
the PNG files with `scripts/render_store_icons.py`; it requires Pillow. Both PNGs
are 8-bit RGB with no alpha channel and use only a solid yellow background plus
near-black artwork, so the 128 px version also stays within the MIP 64-color
guidance.

These store assets are separate from the monochrome 62 × 62 launcher resource in
`resources/drawables/launcher.svg`. Changing a store image does not change the
on-watch app icon or circular-window logo.
