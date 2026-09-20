# Connect IQ Store assets

The two PNGs use the same black radiation-trefoil geometry and solid yellow
background. They contain no text, transparency, Garmin marks or third-party
wordmarks or logos.

| File | Purpose | Dimensions |
| --- | --- | ---: |
| `store-icon.png` | Connect IQ Store listing icon | 500 × 500 px |
| `on-device-store-icon.png` | Connect IQ on-device store icon | 128 × 128 px |

Editable sources are `store-icon.svg` and `on-device-store-icon.svg`. Regenerate
the PNG files with `scripts/render_store_icons.py`; it requires Pillow. Both PNGs
are 8-bit RGB with no alpha channel and use only a solid yellow background plus
near-black artwork, so the 128 px version also stays within the MIP 64-color
guidance.

These store assets are separate from the monochrome 62 × 62 launcher resource in
`resources/drawables/launcher.svg`. Changing a store image does not change the
on-watch app icon or circular-window logo.
