# Roadmap

What exists today is in [README.md](README.md). This file lists the next
tasks in recommended order, with the reasoning and rough scope for each.

## Priority 1 — accuracy of what we already show

1. **Correct centre for wide channels.** The spectrum draws each network
   centred on its primary channel. For 80/160 MHz the real centre is the middle
   of the block (e.g. channel 42 for 36–48, channel 50 for 36–64). Derive the
   block from primary + width using `Band.blocks(widthMHz:)` and centre the
   curve there. Affects the spectrum and the overlap scoring. *Small.*
2. **Use HT/VHT/HE operation elements for width and centre.** CoreWLAN's
   `channelWidth` is sometimes unknown; the VHT Operation (192) and HE
   Operation (255/36) elements carry the exact segment centre frequencies.
   Extend `NetworkCapabilities` and prefer these when present. *Medium.*
3. **Regulatory domain awareness.** DFS/weather classification is hard-coded
   to the common FCC/ETSI pattern. Read the country code from the connected
   AP's Country element and adjust (e.g. Japan channel 14, regions where 116
   or 132–144 are unavailable, 6 GHz availability). *Medium.*
4. **Own-router detection when Location is denied.** Without BSSIDs the
   sibling heuristic is weak. Fall back to matching hidden networks by
   identical beacon interval + width + RSSI within 2 dB. *Small.*

## Priority 2 — features users ask for next

5. **Roaming / BSSID change log.** Record every change of the connected BSSID
   with timestamp, old/new RSSI and channel. Explains mesh hand-offs and
   sudden drops. Show as a timeline under History. *Medium.*
6. **Menu-bar extra.** Live RSSI, link rate and channel of the connected
   network in the menu bar, with a popover for the top neighbours. Uses
   `MenuBarExtra`. *Medium.*
7. **Site-survey mode.** A "Record" button that tags samples with a
   user-entered room name; a summary table of mean/min RSSI per room per
   network, exportable to CSV. Builds on `ScanStore.history`. *Medium.*
8. **Gateway latency alongside RSSI.** Ping the router (from
   `InterfaceStatus.router`) every few seconds and plot latency and loss on a
   second axis in History, to separate radio problems from router problems.
   Needs a raw ICMP socket or `SimplePing`-style implementation. *Medium.*
9. **Alerts.** User notification when the connected RSSI drops below a
   threshold for more than N seconds, or when the router changes channel.
   *Small.*

## Priority 3 — Bluetooth depth

10. **Decode more advertisement types.** Apple Continuity sub-types (AirPods
    battery levels, Find My status), Google Fast Pair, Microsoft Swift Pair,
    iBeacon UUID/major/minor, Eddystone. Gives the Type column real meaning.
    *Medium.*
11. **Merge rotating identifiers.** Devices rotate their random address every
    ~15 minutes and reappear as new dots. Use manufacturer-data fingerprints
    (e.g. identical Find My payload prefixes) to link successive identities.
    *Medium, heuristic.*
12. **Connect and enumerate services.** Optional per-device action to connect
    and list GATT services/characteristics (device information, battery).
    *Medium; changes permission footprint.*

## Priority 4 — polish and distribution

13. **Sortable, filterable table.** `Table` `sortOrder` binding plus a search
    field and band/security filters. *Small.*
14. **Persist history across launches.** Write `ScanStore.history` and
    presence to disk (JSON or SQLite) so long-term trends survive restarts,
    with a retention setting. *Medium.*
15. **App icon and real signing.** Design an icon; sign with a Developer ID
    and notarise so the Location/Bluetooth permissions survive rebuilds and
    the app can be shared as a DMG. *Small, needs an Apple Developer account.*
16. **Localisation.** Strings are English-only; wrap in `String(localized:)`
    and add Hebrew. *Small.*
17. **Tests for views.** Snapshot tests of `SpectrumView` and
    `BluetoothRadarView` with fixture data to catch layout regressions.
    *Medium.*

## Known limitations worth documenting for users

- Distance estimates use a textbook path-loss model; treat as an order of
  magnitude.
- Bluetooth LE only; classic Bluetooth devices do not appear.
- The recommendation cannot know which channels a specific router firmware
  exposes; some drop 116 and 132–144 in addition to the weather channels.
- Ad-hoc signing means macOS may re-ask for Location/Bluetooth permission
  after rebuilds.
