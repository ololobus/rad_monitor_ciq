# Production and beta releases

RadMonitor has four permanent Connect IQ application identities. Production and
beta builds share source code, but each product/channel pair has its own UUID,
manifest, Store listing, install name, PRG, and IQ package. No source or manifest
editing is needed when switching channels.

| Product | Channel | Display name | UUID | Jungle file |
| --- | --- | --- | --- | --- |
| Watch app | Production | RadMonitor | `3d1a9018d56f47b399c106d69763baee` | `monkey.jungle` |
| Watch app | Beta | RadMonitor Beta | `14328308581d4cadb2b8b9f7274dd1a6` | `monkey-beta.jungle` |
| Data field | Production | RadMonitor Field | `03acde44967a408aafdbe2795d25447c` | `datafield/monkey.jungle` |
| Data field | Beta | RadMonitor Field Beta | `81f6e24d93104f92ac7270b64769d925` | `datafield/monkey-beta.jungle` |

Treat these UUIDs as permanent. A package must always be uploaded to the Store
listing with the matching UUID. Do not copy one UUID over another to make a
release. Keep the same developer signing key as well; losing it prevents normal
updates to installed applications.

## Local PRG builds

Build one independently:

```sh
./scripts/build.sh app-production
./scripts/build.sh app-beta
./scripts/build.sh field-production
./scripts/build.sh field-beta
```

The outputs are:

```text
bin/rad_monitor-app-production.prg
bin/rad_monitor-app-beta.prg
bin/rad_monitor-field-production.prg
bin/rad_monitor-field-beta.prg
```

PRGs are for the simulator or USB sideloading. The shorter aliases
`./scripts/build.sh app` and `./scripts/build.sh field` still build the
production variants. Running `./scripts/build.sh` with no argument also builds
the production watch app.

## Store IQ exports

Export exactly one upload package:

```sh
./scripts/export.sh app-production
./scripts/export.sh app-beta
./scripts/export.sh field-production
./scripts/export.sh field-beta
```

The matching packages are written under `dist/`:

```text
dist/rad_monitor-app-production.iq
dist/rad_monitor-app-beta.iq
dist/rad_monitor-field-production.iq
dist/rad_monitor-field-beta.iq
```

`./scripts/export.sh all` exports all four, but individual commands are safer
for normal releases because the selected channel is explicit. Export performs a
normal single-device build first, then creates Garmin's multi-device Store
archive from the same manifest and source.

## Store upload mapping

Upload each file only to its corresponding Connect IQ Store listing:

| Package | Store listing UUID |
| --- | --- |
| `rad_monitor-app-production.iq` | `3d1a9018d56f47b399c106d69763baee` |
| `rad_monitor-app-beta.iq` | `14328308581d4cadb2b8b9f7274dd1a6` |
| `rad_monitor-field-production.iq` | `03acde44967a408aafdbe2795d25447c` |
| `rad_monitor-field-beta.iq` | `81f6e24d93104f92ac7270b64769d925` |

Create separate beta Store listings for the two beta UUIDs and keep them private
for testing. Create or update the two production listings with the production
packages when they are ready for public review. Future beta tests and production
updates use the same four commands and the same four listings.

Production and beta variants can be installed independently because their UUIDs
and private storage are different. Do not run the watch app and data field, or
production and beta copies, against the same Radiacode simultaneously: only one
Connect IQ application should own the BLE connection at a time.

## Release checklist

1. Run `./scripts/test.sh` and `./scripts/test-field.sh`.
2. Export the intended product/channel with `scripts/export.sh`.
3. Confirm the output filename and the destination listing UUID using the table
   above.
4. Upload the `.iq` file. Never upload a sideload `.prg` to the Store.
5. Install the beta or production listing through Garmin Connect IQ and perform
   the relevant hardware/workout checks before broadening availability.
