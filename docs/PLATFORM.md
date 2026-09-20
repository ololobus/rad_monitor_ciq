# Garmin platform findings

Evidence inspected 2026-09-19: current official Garmin API pages, SDK 9.2.0's
bundled documentation and samples, and the installed device definition. The
web Core Topics pages were largely navigation-only in the retrieved version;
the installed SDK contains the full guides referenced below.

## Exact target and memory

Local `~/Library/Application Support/Garmin/ConnectIQ/Devices/instinct3solar45mm/`:

| Source / field | Observed value |
| --- | --- |
| `compiler.json`: `deviceId` | `instinct3solar45mm` |
| `displayName` | Instinct® 3 Solar 45mm / 50mm |
| `deviceVersion` | `3d0fb192a2cf01699aefd0f384af3f527e5885bd` |
| Display | 176 × 176, 1 bit, MIP, upper-right subscreen |
| Watch-app memory limit | 131072 bytes (128 KiB) |
| Glance memory limit | 32768 bytes (32 KiB) |
| Device group | API level 6.0 |
| `simulator.json`: glance content | 164 × 61 at (9,19) |
| `simulator.json`: `glance.liveUpdates` | **true** |

The user confirmed the app running on a Tactical Solar. The installed definition
supplies the shared Solar product ID, not a separate Tactical ID. The app does
not target AMOLED models.

## BLE requirements

- [`Toybox.BluetoothLowEnergy`](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
  requires the `BluetoothLowEnergy` manifest permission and lists this Solar
  family and **Glance** runtime support.
- Register expected service/characteristic/descriptor UUIDs first; only registered
  attributes are exposed. Wait for `onProfileRegister` success before scanning.
  The documented profile limit is **3**; this app uses **1**, with **2**
  characteristics and **1** descriptor. No separate numerical characteristic
  ceiling was found in the current API reference; it is **not asserted here**.
  Registration/resource errors are surfaced rather than assuming unlimited space.
- Install a `BleDelegate`, scan with `setScanState`, select a `ScanResult`, call
  `pairDevice`, and wait for `onConnectedStateChanged`. `getService` and registered
  characteristics are then resolved. There is no invented service-discovery
  callback. `DISCOVERING` is our explicit synchronous lookup state.
- [`Characteristic.requestWrite`](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy/Characteristic.html)
  supports no long writes and throws over **20 bytes**. No larger negotiated MTU
  is assumed. The Radiacode port writes <=18 bytes, matching upstream.
- Subscribe through [`Descriptor.requestWrite`](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy/Descriptor.html)
  on the CCCD, then process notification data in
  [`BleDelegate.onCharacteristicChanged`](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy/BleDelegate.html).
  This protocol uses writes/notifications; characteristic reads are not needed.
- Connection slots are queried with `getAvailableConnectionCount` and logged.
  Profile registration is retained for reconnects; successful profiles are not
  registered again. Error recovery and normal app termination call
  `unpairDevice`, releasing the Radiacode immediately for another client. The
  detector may signal this disconnect with its own beep. No persistent bonding
  is requested.

## Glance decision

`AppBase.getGlanceView()` returns the lightweight `GlanceView`. Selecting the
entry is Garmin's normal transition to the full app. The full app creates its
controller only in `getInitialView`; app `onStart` does not scan. This avoids
starting BLE merely because Garmin started the app to render a glance.

The SDK's `doc/docs/Core_Topics/Glances.html` describes two lifecycle models:
ongoing live UI updates and short background-style renders that terminate after
rendering. It explicitly cautions against assuming a glance-to-full-app startup
sequence. The installed target's `liveUpdates: true` is evidence for live UI
updates, despite generic guide shorthand about non-music devices. It is **not a
BLE connection-lifetime guarantee**.

[`GlanceView`](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/GlanceView.html)
has a restricted drawing context and does not support page controls/layers. The
app's `:glance` annotations retain only the app entry, storage helper and glance
view in the reduced runtime. A 30-second timer reloads stored values while visible and
is stopped on hide. The glance allocates no transport, response buffers or
controller. It never labels its stored reading as a live connection.

**Strategy A remains experimental:** the API lists scanning/connecting capability
in Glance, so we do not claim those operations are forbidden. Practical scan,
subscription, initialization and polling latency, focus behavior and battery
cost need measurements on the watch. The docs inspected do not promise that a
BLE connection survives the glance/full-app transition. This implementation
neither depends on that nor attempts a handoff: foreground exit stops BLE;
foreground entry starts a fresh session.

**Strategy B is implemented:** Application.Storage holds a versioned dictionary
with dose rate, raw dose rate, CPS, uncertainties, timestamp and flags, plus an
independent status dictionary for detector battery and persistent app-active
dose/duration. Each foreground run starts a new timing baseline, so closed time
is not integrated. The glance reads the same app's
persistent store, with type checks; there is no shared in-memory controller or
inter-app storage assumption. Save at most every 15 seconds, when status changes,
and on clean exit.
The SDK Glances guide explicitly supports application storage in glance mode.
[`Storage`](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
supports these scalar/dictionary values. App Properties are for static settings
and are not used as a telemetry channel. Missing or incompatible glance fields
display `--`. The full measurement screen treats the protocol's accepted
five-second timestamp skew as current and reports “Clock changed” only for a
larger clock reversal.

## Simulator and remaining hardware questions

The SDK's `doc/docs/Core_Topics/Bluetooth_Low_Energy.html` describes a Nordic
**nRF52 DK or nRF52840 dongle**, Garmin connectivity firmware, and a configured
serial port in Simulator BLE Settings. SDK 9.2.0 has different firmware links
than older SDKs. Built-in Mac Bluetooth is not the simulator BLE transport.

Native tests verify Monkey C execution with generated binary fixtures and a
fake GATT boundary. Physical photos/reports additionally confirm connection,
measurement rendering, glance launch, menus and the current Solar layout. They
do not establish behavior for other detector firmware/models, repeated GATT
recovery, detector unit scaling, flash persistence across power loss, or battery use.
See [HARDWARE_TEST.md](HARDWARE_TEST.md). A live-glance experiment is deferred;
there is no live-glance code path in this build.
