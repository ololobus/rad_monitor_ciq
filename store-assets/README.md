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

The production watch-app cover uses the core yellow live-monitor treatment.
The production field cover emphasizes workout routing and dual history plots.
Both beta covers use blue/cyan diagnostic styling and a prominent `BETA` mark
so they cannot be mistaken for production during upload. All four covers use a
restrained, minimal palette, are opaque 8-bit RGB PNGs, and are kept below the
Connect IQ submission limit of 300 KB.

Editable sources are `store-icon.svg` and `on-device-store-icon.svg`. Regenerate
the PNG files with `scripts/render_store_icons.py`; it requires Pillow. Both PNGs
are 8-bit RGB with no alpha channel and use only a solid yellow background plus
near-black artwork, so the 128 px version also stays within the MIP 64-color
guidance.

These store assets are separate from the monochrome 62 × 62 launcher resource in
`resources/drawables/launcher.svg`. Changing a store image does not change the
on-watch app icon or circular-window logo.
