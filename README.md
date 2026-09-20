> [!IMPORTANT]
> **This project is 100% vibe-coded**. It's audited by an independent agent pass for any security, privacy,
> and legal concerns; and it seems to work well for my specific setup, but use it on your own risk.
> If you have different devices from mine, feel free to reach out, compile, test, and/or open PR.

# RadMonitor

A small MIT-licensed Connect IQ watch app that talks directly to a Radiacode 10x
via BLE. The current field-test detector is a Radiacode 102. It displays dose rate and CPS with uncertainty, accumulated dose and duration,
battery status, retained history, and a stored numeric glance. No phone relay or runtime dependencies.

RadMonitor is an independent, unofficial open-source project. It is not
affiliated with, endorsed by, or sponsored by Garmin Ltd. or RADIACODE LTD.
Garmin and Connect IQ are trademarks of Garmin Ltd. or its subsidiaries;
Radiacode is a trademark of RADIACODE LTD. See the [privacy policy](PRIVACY.md).

**Status:** verified on an Instinct 3 Tactical Solar against a physical
Radiacode running firmware 4.14. BLE connection, live dose rate/CPS, detector
battery, accumulated dose, retained history, glance rendering, native menus and
the Solar circular-window layout have all been exercised on the watch. Native
Monkey C protocol/session/rendering tests also run in Garmin's simulator. See
[validation](docs/VALIDATION.md) for the remaining limits.

## Supported hardware

- Initial target: **Instinct 3 Tactical Solar (monochrome)**. The installed Garmin
  device definition identifies both Solar sizes as **`instinct3solar45mm`**
  (display name “Instinct® 3 Solar 45mm / 50mm”). No guessed Tactical product ID.
- Radiacode **10x**, using the current `cdump/radiacode` record layout, with
  detector firmware **4.8 or newer**. Firmware 4.14 has been tested physically;
  the exact detector model used for that test was not recorded. Older firmware
  is rejected.
- Built with **Connect IQ SDK 9.2.0**, the stable release listed by Garmin at setup.

## Build

Install [Garmin SDK Manager](https://developer.garmin.com/connect-iq/sdk/), select
SDK 9.2.0, and install the **Instinct 3 Solar 45mm / 50mm** device definition.
Install Java 17 (Java 11+ is required by Garmin's command-line guide).

```sh
./scripts/build.sh
```

Output: `bin/rad_monitor.prg`. The script reads the active SDK from Garmin's macOS
configuration, or uses `CIQ_SDK`. Set `JAVA_HOME` if needed. This workspace already
has a project-local Temurin 17 runtime under `.tools/`, which the script detects.
The runtime and SDK are not part of the repository.

The first build creates an RSA signing key in `.keys/developer_key.der` with
private permissions. Keep that key for subsequent builds; it is ignored by Git.
Use `CIQ_DEVELOPER_KEY=/path/to/key.der` to supply your own existing key.

To reproduce the local Java setup on Apple Silicon:

```sh
mkdir -p .tools
curl -fL 'https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse' -o /tmp/rad_monitor-jdk.tar.gz
tar -xzf /tmp/rad_monitor-jdk.tar.gz -C .tools
```

For tests, open the SDK's Connect IQ simulator, then:

```sh
./scripts/test.sh
```

For a normal simulator launch from the repository root:

```sh
source scripts/env.sh
monkeydo bin/rad_monitor.prg instinct3solar45mm
```

The simulator requires Garmin's supported **Nordic BLE adapter and firmware** for
real BLE; it does not use the Mac's built-in Bluetooth. Without an adapter,
expect a BLE diagnostic/retry screen. Protocol tests use synthetic bytes and a
fake transport; they require no detector. See [platform notes](docs/PLATFORM.md).

## Sideload on your watch

1. Build the app. Connect the watch with a USB data cable. On the watch, hold
   **MENU → System → USB Mode → MTP** if necessary.
2. Open its internal storage. On macOS use an MTP-capable file-transfer client;
   do not assume the watch appears as a Finder volume. Close Garmin Express if
   it prevents another client from accessing the device.
3. Copy `bin/rad_monitor.prg` into **`GARMIN/APPS/`**, naming it
   **`RADMONIT.PRG`**. The shortened basename respects the watch's eight-character
   sideload filename convention. Do not copy the test PRG or debug XML.
4. For diagnostics, create an empty **`GARMIN/APPS/LOGS/RADMONIT.TXT`** before
   launching. The name must match the PRG basename. `System.println` writes there.
5. Disconnect USB cleanly. Press **GPS**, find **RadMonitor** in the apps list
   (add it to favorites if desired), and open it.
6. To add its glance, edit the watch's normal glance loop and add **RadMonitor**.
   Selecting the glance should launch the full app through Garmin's normal flow.

Use the same PRG filename when replacing a build. No store publication or phone
companion is required. [Garmin's USB mode documentation](https://www8.garmin.com/manuals-apac/webhelp/instinct3/EN-SG/GUID-5E0E6DEF-C4DA-4D42-874C-3E2173361BFE-2591.html).

For Connect IQ Store publication, export an `.iq` package rather than uploading
the sideload `.prg`. Ready-to-upload icon PNGs and their editable SVG sources are
in [`store-assets/`](store-assets/README.md).

## First hardware test

1. Turn on Radiacode Bluetooth and disconnect its phone/desktop clients. Keep
   **only one Radiacode nearby**: this version selects the first matching service
   UUID or `RadiaCode` advertised name, then verifies the registered GATT profile.
2. Open the full watch app. Expected flow:
   `REGISTERING → SCANNING → CONNECTING → DISCOVERING → SUBSCRIBING → INITIALIZING → READY`.
3. Wait for dose rate and CPS. Polling is every two seconds after the previous
   reply. Compare both readings with the detector over several updates.
   **Dose conversion is upstream's exporter factor, raw × 10,000 → µSv/h; verify
   this on your detector/firmware and display-unit setting.** Raw dose and flags
   are retained in the log. See [protocol notes](PROTOCOL.md#measurements-and-units).
4. Hold **MENU** for **Connected devices**, **Diagnostics**, **Info**, and **Settings**.
   Use UP/DOWN to select a section and GPS to open it. Details scroll with
   UP/DOWN; BACK returns. Info includes version and UTC build time.
   From the main screen, UP/DOWN cycles dose rate → CPS → accumulated dose/duration → history plot.
   **BACK** returns. On an error, **GPS** requests an immediate retry; automatic
   delays are 5, 10, 20, then 30 seconds. Turning the detector off and back on
   should recover without restarting the watch app.
5. Exit the full app and inspect its glance: the last stored measurement must
   show the stored dose rate (µSv/h), CPS and detector battery (%). Relaunch through the glance, obtain a
   new reading, exit, and check that the cache changed.
6. Send the log plus watch/detector firmware versions and any clipping/µ-symbol
   problems. For an IQ crash, also retain `GARMIN/APPS/LOGS/CIQ_LOG.YAML` and the
   matching local `.prg.debug.xml`.

[Detailed hardware checklist](docs/HARDWARE_TEST.md).

## Architecture and current scope

- `RadiacodeBleTransport.mc`: registered service, scan, connection, CCCD
  subscription, serialized 18-byte writes, notifications, explicit states.
- `RadiacodeProtocol.mc`: framing, echoed command/sequence validation, firmware
  parsing, mixed data-buffer parsing. Independent of BLE and UI.
- `RadiacodeController.mc`: initialization, one outstanding command, polling,
  deadlines, retry backoff, sample freshness and cache writes.
- `MainView.mc`: four high-contrast measurement/history screens.
- `MeasurementStore.mc` / `RadMonitorGlance.mc`: independent persistent measurement/status caches, legacy status migration, and the RadMonitor numeric glance.

**Strategy B: stored-data glance.** The full app owns BLE and stops it on exit; the
 glance reads storage and allocates no transport/controller. It reloads stored data
 every 30 seconds while visible and alive. The installed target supports live
 glance updates and Garmin lists BLE in the Glance runtime. That does **not**
 establish reliable scan/connect/read timing or connection survival through
 transitions. Those remain hardware questions, not claims of API prohibition.

Limits: one detector, no background measurement collection, no spectrum,
FIT recording or alarms. This is an informational third-party display, not
calibrated safety or medical equipment. Replies are capped at 8 KiB to protect the watch heap;
unknown/malformed records fail visibly rather than silently misaligning the
parser. A large backlog may therefore require reconnecting/clearing the backlog
with another client. Initialization sets the detector's local clock and device
time register, following upstream; it does not reset dose or spectrum. Cached
values are saved at most every 15 seconds and again on clean exit. Abrupt shutdown
can leave an older cache.

See [PROTOCOL.md](PROTOCOL.md), [platform findings](docs/PLATFORM.md),
[LICENSE](LICENSE), and [upstream MIT attribution](THIRD_PARTY_NOTICES.md).

## Screens and retained history (0.3.1)

The standard radiation trefoil is the launcher icon and occupies the small
circular window on all four main screens by default. The live values are shifted left into the
main display area. Menus use that window for selection/scroll position, with
body text below the cutout. Diagnostics and device/build details scroll.

UP or DOWN cycles dose rate with percentage uncertainty, CPS with percentage
uncertainty, accumulated dose (µSv) with duration, and the **µSv/h** plot.
Hold MENU → Settings → Window data to choose Logo or Device battery. The saved
battery option draws a circular progress bar and a one-line percentage capped
at `99%`. Missing battery or uncertainty is shown as `--`. Battery comes from
the detector's periodic RareData status. The app tries all three known read-only
forms of the detector's `DS_uR` register. Firmware that does not expose it uses
RareData as an authoritative anchor and advances that value from timestamped
detector-buffer records. Consequently, measurements recorded by the detector
while the watch was disconnected are included after reconnection. A detected
`DOSE_RESET` event immediately clears the cache and starts a new anchor.
Diagnostics reports `Dose raw N uR` followed by `(generic)`, `(batch)`, or
`(single)` after a successful direct read. When every command fails, successful
history reconstruction is reported as `Dose buffered N.NNN uSv`.

The plot stores the latest **360 ten-second recording bins**, using the mean dose
rate per bin. This is the last hour of measurements actually collected, not the
last wall-clock hour: time spent disconnected or with the app closed consumes no
slots. Retained samples are drawn continuously, scale vertically from their
observed minimum to maximum, put the current reading and unit at the top, and
keep the complete graph below the Solar circular window. No measurements are
invented while the app is closed.

History is stored in a separate compact 4.3 KB application-storage value, with
no age expiry. It saves alongside the reading every 15 seconds and on clean
exit. New recording eventually replaces the oldest bins; this is a retained
rolling hour, not an unlimited archive. Uninstalling/clearing application data
removes it, and an abrupt shutdown may lose the last 15 seconds. Keep the same
app identity and signing key when replacing builds.
