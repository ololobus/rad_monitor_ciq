# Hardware and visual acceptance checklist

Use `bin/rad_monitor.prg` and keep its matching `.prg.debug.xml`. Record watch model,
watch software/CIQ version, detector model and firmware, detector dose/count
units, and app build date. The SDK/device files only establish compile support.
User photos and reports have confirmed the current layout, live values, detector
battery, glance and native-menu behavior on an Instinct 3
Tactical Solar. The checklist remains useful for release regression testing;
items that need logs, repeated cycles or a controlled reset are not implied by
those visual checks.

## Full app

- Enable Radiacode BLE, disconnect the phone app and other clients, keep one
  detector nearby. Log the advertised name, RSSI and available BLE slots.
- Confirm the title avoids the Solar display's circular cutout, numbers fit,
  µ renders, and error text remains readable. The current geometry was adjusted
  from physical-watch photos; retest it after any font or coordinate change.
- Follow REGISTERING, SCANNING, CONNECTING, DISCOVERING, SUBSCRIBING,
  INITIALIZING and READY in the text log. Hold MENU, choose Diagnostics, and press GPS to open details.
- Confirm each initialization reply matches the requested command/sequence;
  expect firmware text and increasing notification count.
- Compare both dose rate and CPS with the physical detector over several
  updates; account for sampling/filtering delays. Compare logged raw dose with
  raw ×10,000. Check Sv/R and CPS/CPM display settings independently. Do not
  assume the detector's screen-unit selection changes the protocol values.
- Normal values must say Live only when READY and sample age is 0–10 seconds.
  Old samples must be marked Stored; zero must display as a real zero.
- Turn the detector off, out of range, and back on. Verify a visible error,
  bounded retry cadence and eventual fresh data. Try 10 reconnect cycles.
- Start with detector off, then turn it on. Try starting with the phone still
  connected, then disconnect it. These cases must recover without an IQ crash.
- GPS on an error should retry without waiting for backoff. BACK exits; reopening
  starts a fresh session and the previous cache remains available.
- Confirm that the app makes no watch-requested tone or vibration. The app has no
  Attention API calls. Normal closure explicitly unpairs so the Radiacode is
  immediately available to another client; the Radiacode 102 may beep to report
  that detector-side disconnect.
- Leave connected for 10 minutes. Check latency, free memory from logs, and
  whether DATA_BUF exceeds 8 KiB. Save any unknown record ID/error verbatim.
- Reconnect after an overnight detector backlog. An unknown record pair such as
  `171/170` may be logged as a skipped tail, but it must not disconnect BLE or
  enter a connect/error loop; the next poll must resume live readings.

## Cached glance

- Before the first sample, verify unknown values show `--`. After a sample, exit
  normally; add RadMonitor to the glance loop and verify cached µSv/h, CPS and
  battery percent, with all three lines fitting.
- Selecting it should open the full app. Returning to the glance must show the
  latest persisted data, not restart BLE or claim Connected.
- Scroll away/back, remain visible over 30 seconds, and leave the glance loop.
  Log/view should confirm no scan requests in glance mode and cache refresh while
  alive. Reboot the watch and confirm persistence; forced exit may lose up to
  the latest 15 seconds of cache writes.
- A normal fresh record up to five seconds ahead must show `0s ago`, not “Clock
  changed.” Move watch time backward by more than five seconds to verify the
  actual warning, then reopen the app to establish a new detector-time base.

## Optional later live-glance experiment (not in this build)

Instrument lifecycle timestamps in a separate development build: app onStart /
getGlanceView / view onShow / onHide / app onStop, plus every BLE state event.
Measure time from visible glance to scan result, CCCD acknowledgement and first
RealTimeData. Test rapid scrolling, >30 seconds visible, opening the app during
each connection phase, leaving and returning, and no detector present. Determine
whether each transition keeps the same device connection or creates a new
runtime. Repeat with other connected watch accessories. Compare battery use
against cached mode over the same interval. Only adopt live mode if repeated
samples fit the observed runtime and battery cost is acceptable.

## Diagnostic collection

Create `GARMIN/APPS/LOGS/RADMONIT.TXT` before running `RADMONIT.PRG`; Garmin does
not create the app text log automatically. Copy it back after the test. Logs
include states, command and sequence, firmware, sample raw/converted dose, CPS,
flags and errors. No detector address is persisted. On an IQ crash collect
`CIQ_LOG.YAML` and keep the exact matching local debug XML for symbolication.
If logging is no longer needed, remove the text log while the app is stopped.

## UI/history regression

- Confirm the trefoil appears in the launcher and small circular window. Confirm
  the glance instead starts with the compact `RADMONITOR` wordmark on black.
- Confirm the main values sit left of the cutout and no title overlaps the window.
- Cycle both directions with UP/DOWN. The plot and live reading both use µSv/h.
- Hold MENU: verify all four sections, GPS selection, BACK, and scrolling through
  long diagnostics/build information. No body text should enter the small circle.
- Record for a few minutes, exit cleanly, then reopen: history should remain.
  Closed/disconnected time must consume no history slots, and retained recorded
  samples should draw continuously with no wall-clock gap. Confirm the chart
  advances as new ten-second bins arrive and stays below the circular window.

## 0.3.3 telemetry/settings regression

- Cycle dose rate → CPS → app-active dose/duration → history in both directions.
  Verify rate and CPS uncertainty percentages against the detector.
- Confirm DOSE advances only while regular foreground replies arrive. Close and
  reopen the app: the value must persist, while closed time must not be added.
  Disconnect for more than ten seconds and reconnect; the gap must not be
  counted. Select **Reset dose** immediately after Settings and confirm both dose
  and duration return to zero. The value is intentionally not expected to match
  the detector's total dose.
- In MENU → Settings → Window data, choose Device battery. Check percentage and
  ring placement in the circular window; switch back to Logo and reopen the app
  to confirm the choice persists. Unknown battery should show `--` until status
  arrives. Confirm the percentage follows the detector, not the watch battery.
- Exercise a detector/watch clock mismatch. A future-dated sample may be logged
  as normalized to receipt time, but must not cause a protocol reconnect, and a
  battery status in that reply must still update.
- Exit/reopen and inspect the glance: all three cached values should persist,
  including battery when the newest poll contained only status data.
