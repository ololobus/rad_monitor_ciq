# Local validation

2026-09-20, macOS Apple Silicon. SDK 9.2.0
(`connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`), Temurin 17.0.20.1,
installed device ID `instinct3solar45mm`.

## Compiler

`./scripts/build.sh` completed successfully with no warnings.

| Compiler metric | Bytes |
| --- | ---: |
| Foreground code | 16370 |
| Foreground static data | 6027 |
| Glance code | 1930 |
| Glance static data | 970 |
| Total PRG file | 131244 |

PRG file size includes resources/metadata/signature and is not runtime RAM.
Compiler code/data sizes exclude runtime heap use. The real watch's live BLE
memory behavior remains unmeasured; free memory is logged when caching samples.
The target limits are 128 KiB foreground and 32 KiB glance.

Final PRG SHA-256:
`534b2ebbe1f9abdd63632ff230808709287998ab849ae29d55b08c7c19a890b4`.

## Native tests

The complete `./scripts/test.sh` run was **30 passed, 0 failed, 0 errors** as
Monkey C on Garmin's Instinct 3 Solar simulator.
[Recorded results](TEST_RESULTS.txt).

- Exact first request and command-counter wrap.
- Reassembly at every possible two-fragment boundary and one byte at a time.
- Oversize/undersize/overflow framing rejection.
- Mixed record parsing, record sequence wrap, newest sample, timestamp conversion,
  flags, float dose conversion and CPS.
- Firmware compatibility gate and byte-length-prefixed strings.
- Empty buffer and the single trailing-zero firmware workaround.
- Unknown record IDs end the decodable prefix without dropping validated data;
  truncated known records, invalid lengths, negative values and NaNs remain fatal.
- Record gaps preserve only validated prefix samples; a subsequent poll succeeds
  on the same session without reconnecting or resetting its command sequence.
- An unknown backlog record such as `171/170` preserves the preceding sample and
  the next poll succeeds on the same BLE session without reconnecting.
- Echoed command/sequence rejection.
- Complete initialization through first poll using the real controller and parser,
  with a fake BLE boundary, including both write/notification callback orders.
- Persistent storage round-trip and cached sample typing.
- Request timeout, explicit retry and stopping before a subsequent retry.

Synthetic fixtures use upstream Python `struct` layouts; they are **not physical
Radiacode captures**. No Python decoder is substituted for the production Monkey C
parser in these tests. Session mocks do not validate Garmin's real GATT stack.

The SDK's `monkeydo` returned exit status 1 even for its explicit all-passed
report on this Mac. The test wrapper handles status 0/1 only when the output
contains a `PASSED (passed=N, failed=0, errors=0)` summary; other results fail.

## Store assets

`scripts/render_store_icons.py` generated `store-assets/store-icon.png` at
500 × 500 and `store-assets/on-device-store-icon.png` at 128 × 128. Both are
8-bit RGB PNGs with an embedded sRGB profile and no alpha channel. The two sizes
were visually inspected after rendering and use identical trefoil geometry.

## Hardware report and remaining validation

The initial physical test on detector firmware 4.14 exposed a filtered-record
sequence gap and reconnect loop. Continuing from structurally valid records,
as upstream does, fixed that failure. Subsequent watch photos and reports confirm
live dose rate/CPS, battery, retained graph, glance, native
menus, pagination, settings and the Solar circular-window layout. The logo/plot
combination also has a native render regression after its earlier IQ crash.
The overnight-backlog `171/170` recovery is simulator-tested but still needs a
repeat on the physical watch and Radiacode 102.

## Not yet validated

Long-duration battery impact, detector firmware/model variants, physical
overnight unknown-record recovery, repeated actual GATT recovery,
flash persistence across power loss, and calibrated dose-rate conversion across
detector unit configurations. There is no Nordic BLE
simulator adapter configured for this task.

See [hardware checklist](HARDWARE_TEST.md) for release regression criteria.

## UI and history checks

Native tests cover ten-second aggregation without stretching bins to the polling
interval, bounded rolling retention, persistent history reload after days away,
pause metadata, malformed-cache handling, main-screen cycling, menu
selection wrap, and rendering every view into a native Garmin graphics buffer.
These rendering calls prove execution without exceptions, not physical visual
legibility. No computer-use access or visual automation was used.

The circular window coordinates are derived from the installed device's
simulator.json: main display origin (101,158), circle origin (214,158), diameter
62. In app coordinates its center is (144,31). Shared screen layout helpers keep
menu/detail content below y=62; the window is independent of the body layout.
Both readings and plot use µSv/h per the user's unit clarification.

## 0.3.3 telemetry checks

Telemetry tests cover RareData field offsets, persistent app-active dose
integration, closed/connection-gap exclusion, explicit reset, clock-skew
normalization without reconnect, independent battery updates, both percentage
uncertainties, status-only replies and cache persistence, record gaps/truncation,
settings persistence, and native drawing of unknown, 0%, 1%, 50%, 99% and 100%
battery states. Navigation covers all four screens and menu sections. Glance
drawing includes all three cached numbers with stock-style left/right anchors.
Timestamp tests distinguish the accepted five-second transport skew from a real
clock reversal. Detector accumulated dose is deliberately not presented.
