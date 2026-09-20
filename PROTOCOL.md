# Minimal Radiacode protocol port

Reviewed against `cdump/radiacode` commit
[`2b217916f49f5eedddf8f0d9116fcfd3c6b8832e`](https://github.com/cdump/radiacode/tree/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e).
This is a subset port, not a new protocol specification. All multibyte integers
and IEEE-754 floats below are little-endian. Upstream MIT notice is retained in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## GATT

| Role | UUID |
| --- | --- |
| Service | `e63215e5-7003-49d8-96b0-b024798fb901` |
| Write without response | `e63215e6-7003-49d8-96b0-b024798fb901` |
| Notifications | `e63215e7-7003-49d8-96b0-b024798fb901` |
| Notification CCCD | `00002902-0000-1000-8000-00805f9b34fb` |

The [current transport](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/src/radiacode/transports/bluetooth.py)
uses Bleak and names the two characteristics, not their parent service. The
service is explicitly verified in the
[immediately preceding bluepy transport](https://github.com/cdump/radiacode/blob/f80760834bb35b0e40530e207d0c8c895ec73fd8/src/radiacode/transports/bluetooth.py).
We did not infer the service UUID by decrementing a characteristic UUID.

Garmin registers this one service, both characteristics, and the notification
CCCD before scanning. It writes `01 00` to the CCCD and waits for successful
`onDescriptorWrite` before initialization. Notification bytes arrive via
`onCharacteristicChanged`; measurements are requested, not unsolicited decoded
GATT readings. Commands are split into **18-byte** writes without response,
following upstream; Garmin write callbacks serialize chunks. All current
requests fit in one such chunk, but the transport supports more.

Name matching follows upstream's
[`examples/scan.py`](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/src/radiacode/examples/scan.py):
`RadiaCode` prefix. The custom service advertisement is an alternate match.
Identification is for discovery, not authentication; use one nearby detector.

## Request and response framing

From [`RadiaCode.execute`](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/src/radiacode/radiacode.py):

```
u32 length        bytes after this prefix, including the four-byte header
u16 command
u8  zero
u8  sequence      0x80 + counter; counter wraps modulo 32
... arguments
```

Responses also begin with a four-byte length and must echo the four-byte request
header exactly. There is **no extra application checksum/CRC** in the upstream
path. Only one request can be outstanding. Notifications can split any field;
the port even tolerates a fragmented length prefix. A 10-second transaction
deadline covers both write completion and reception. Replies under four bytes,
over 8192 bytes, overflow, wrong commands/sequences, and unexpected notifications
produce a diagnostic and disconnect. A new session starts its sequence at zero.

First request (SET_EXCHANGE), shown as hex:

```
08 00 00 00  07 00 00 80  01 ff 12 ff
```

## Minimal initialization and polling

IDs come from
[`types.py`](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/src/radiacode/types.py),
and ordering/arguments from `RadiaCode.__init__`, `set_local_time`, `device_time`,
`fw_version`, `read_request`, and `data_buf` in `radiacode.py`.

| Step | Command | Payload / validation |
| --- | --- | --- |
| Enable exchange | `SET_EXCHANGE = 0x0007` | `01 ff 12 ff`; validate echoed header |
| Set local clock | `SET_TIME = 0x0a04` | 8 bytes: day, month, year−2000, 0, second, minute, hour, 0 |
| Set device time | `WR_VIRT_SFR = 0x0825` | u32 `DEVICE_TIME = 0x0504`, u32 zero; reply u32 status must be 1 |
| Firmware gate | `GET_VERSION = 0x000a` | Boot and target: u16 minor, u16 major, u8 string length, string bytes. Require target >=4.8 |
| Poll accumulated dose | `RD_VIRT_STRING = 0x0826`, `RD_VIRT_SFR_BATCH = 0x082a`, then legacy `RD_VIRT_SFR = 0x0824` | u32 `VSFR.DS_uR = 0x8022`; validate response shape before reading u32 µR |
| Poll data | `RD_VIRT_STRING = 0x0826` | u32 `VS.DATA_BUF = 0x0100` |

`SET_EXCHANGE` and `SET_TIME` reply payloads are not interpreted upstream and
are not assigned invented status semantics here. Spectrum-format configuration
is unnecessary for this subset and is omitted. Dose/spectrum reset, display-unit
changes and alarm writes are not implemented.

After the device-time acknowledgement, the timestamp base is watch UTC epoch
seconds +128, exactly following upstream's relative-time convention. Local
calendar fields are used for SET_TIME; record offsets are independent of time
zones. Record timestamps are kept to one-second precision for freshness, not
replaced by receipt time. Unexpected timestamps more than five seconds in the
future cause an error. The UI clamps the accepted zero-to-five-second future
skew to `0s ago`; only a larger negative age is labeled `Clock changed`.

A virtual-string reply after its echoed header contains u32 status (=1), u32
payload length, then the payload. The port implements upstream's special case
allowing exactly **one extra trailing zero byte** beyond the declared length.

## Measurements and units

From
[`decode_VS_DATA_BUF`](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/src/radiacode/decoders/databuf.py):
records have `<BBBi>` = u8 sequence, u8 event ID, u8 group ID, signed i32 offset
in **10 ms** units. Record sequence wraps modulo 256 within each buffer.

Event 0 / group 0 is `RealTimeData`. Its 15-byte payload is `<ffHHHB>`:

| Offset within payload | Field |
| --- | --- |
| 0 | Float32 count rate (CPS) |
| 4 | Float32 raw dose rate |
| 8 | u16 count-rate error (÷10 gives percent) |
| 10 | u16 dose-rate error (÷10 gives percent) |
| 12 | u16 flags |
| 14 | u8 real-time flags |

The app picks the newest RealTimeData timestamp, displays CPS directly, and
uses **raw dose ×10,000** for µSv/h, matching upstream's
[`radiacode-exporter.py`](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/src/radiacode/examples/radiacode-exporter.py).
For example raw `0.0000087` becomes `0.087 µSv/h`.

**Evidence boundary:** upstream's newer
[measurement guide](https://github.com/cdump/radiacode/blob/2b217916f49f5eedddf8f0d9116fcfd3c6b8832e/docs/guides/measurements.md)
warns that raw values require an explicit device-configuration-aware conversion.
The fixed exporter factor is the implemented starting point, not a verified
claim across every firmware/unit configuration. Compare the physical detector
and log in both Sv and R display modes before declaring this port validated.
Raw dose and flags are preserved. Flags are logged without inventing validity
bit meanings. Dose-rate and count-rate uncertainties are displayed as the supplied percentage (raw u16 ÷10); no confidence level is inferred. Nonfinite/negative rates
are rejected; genuine zero readings are retained.

Event 0 / group 3 (`RareData`) has a 14-byte `<IfHHH>` payload:

| Offset | Field / conversion |
| --- | --- |
| 0 | u32 accumulated-dose duration, seconds |
| 4 | Float32 accumulated dose; raw ×10,000 displayed as µSv |
| 8 | u16 temperature; (raw−2000)/100 °C |
| 10 | u16 battery; raw/100 percent |
| 12 | u16 flags |

Accumulated-dose scaling uses the same raw-unit convention as dose rate and
still requires comparison with the physical detector. Raw accumulated dose is
retained and logged. Battery, total dose and duration are cached independently
of RealTimeData, including replies containing only RareData. They remain unknown
until the first such record; their update interval is controlled by the detector.
Temperature is decoded but not displayed.

The app requests `DS_uR` (`0x8022`) first with generic `RD_VIRT_STRING`
(`0x0826`), then automatically retries a rejected generic read with upstream's
typed `RD_VIRT_SFR_BATCH` (`0x082a`), followed by the declared legacy single
register command `RD_VIRT_SFR` (`0x0824`). It polls immediately after each
connection and once per minute thereafter. A successful generic response contains u32
result `1`, u32 byte count `4`, and the detector's u32 micro-roentgen total; a
successful batch response contains validity mask `1` followed by that total. The
single-register response accepts only the known raw/status/length shapes. The
100 µR/µSv convention converts that value to µSv. Because this register belongs
to the detector, it includes dose accumulated while the watch was disconnected.
As in upstream `read_request`, one trailing zero byte beyond the declared length
is accepted to accommodate the current firmware response quirk.
If every register form is unavailable, the app never substitutes connected-only
integration. It anchors on the newest RareData total and integrates subsequent
timestamped RealTimeData and DoseRateDB records from the detector buffer. Those
records include data collected while the watch was disconnected. The persisted
last detector timestamp prevents replayed buffers from being counted twice;
reset and power events delimit integration, and gaps over five minutes are not
bridged.
The former `device-status-v1` cache is migrated so an upgrade does not hide the
last known detector battery.

Event 4 / group 7 is `DOSE_RESET`. While the app is connected, that event clears
the cached accumulated dose and duration immediately and establishes a timestamp
barrier so older buffered RareData cannot restore the pre-reset value. A reset
performed while the app is closed is reflected by the reset event and following
buffered records after reconnection; the watch cannot observe it while stopped.

RareData packet timestamps can be far in the past while the detector drains its
buffer. The app therefore orders cumulative status primarily by accumulation
duration, not by a short wall-clock freshness cutoff. This prevents an old
stored total from remaining on screen for hours. The packet timestamp is retained
as `sourceTimestamp`; the visible "Updated" age starts when the status was received.

Other known records are skipped using upstream lengths, so their bytes are not
misread as RealTimeData:

- Event 0, groups 0–9 payload sizes: **15, 8, 16, 14, 16, 16, 6, 4, 6, 6** bytes.
- Event 1, groups 1–3: u16 sample count + u32 sample time, followed by count ×
  **8, 16, 14** bytes respectively.

A record-sequence gap is recorded in diagnostics, but parsing continues from the
next structurally valid record. Filtered exchanges can legitimately omit records
while the detector's sequence counter still advances; stopping at that gap can
discard a later RareData record containing battery and accumulated dose. A buffer
without RealTimeData does not update the rate cache, while valid RareData anywhere
in the buffer updates the independent status cache. The first gap is logged with
expected/actual sequence, byte offset, remaining bytes, event and group IDs.
Command-echo sequence mismatches still fail the transaction, and unknown or
truncated records still reject the whole reply.
Large backlogs over 8 KiB are not streamed/skipped yet. Poll interval is two
seconds after each completed reply, with no overlapping command queue. The UI
timer also runs at two seconds, matching the measurement cadence rather than
forcing an extra repaint every second.
