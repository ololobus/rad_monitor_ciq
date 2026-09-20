# RadMonitor privacy policy

Last updated: September 20, 2026

RadMonitor communicates directly with a compatible Radiacode detector over
Bluetooth Low Energy. It reads radiation measurements, detector status,
detector battery level, and detector-provided timestamps needed to display the
app's measurements and retained history.

The RadMonitor watch app stores a limited measurement and status cache in the app's private
storage on the watch. This supports its glance, recent-history graph, and
recovery after the app is closed. The cache remains on the watch and is removed
when the user uninstalls the app or clears its application data.

The separately installed RadMonitor workout data field writes dose-rate and CPS
developer fields into the Garmin activity FIT file while the native activity
timer is running. Garmin software may sync and process that activity according
to the user's Garmin account and privacy settings. This data is not sent to or
made accessible to the RadMonitor developer.

RadMonitor does not collect location, Garmin account information, contact
information, device serial numbers, or Bluetooth addresses. It has no analytics,
advertising, cloud service, phone relay, or developer-operated server. Apart
from the user-controlled Garmin activity recording described above, it does not
transmit detector measurements or other user data to the developer or any third
party.

Diagnostic logging is disabled unless the user manually creates the app's text
log on the watch. A diagnostic log can contain detector readings, protocol
status, firmware version, and error details. It does not intentionally record a
detector Bluetooth address. The user controls whether that file is created,
copied, shared, or deleted.

RadMonitor is an independent project and is not affiliated with Garmin Ltd. or
RADIACODE LTD. Questions about this policy may be raised through the public
issue tracker for the source repository.
