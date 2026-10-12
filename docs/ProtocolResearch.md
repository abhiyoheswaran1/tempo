# Protocol research and attribution

Research date: 2026-10-12. Public main-branch references can evolve; evidence is version bounded. No physical Tempo captures have been obtained. All test packets in this repository are constructed examples, not recorded hardware fixtures.

Sources inspected:
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL.md — central scope and firmware boundaries.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_CONCEPTS.md — standard SIG services and integrity contracts.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_WHOOP4.md — 41.17.6.0 / 17.2.2.0 services and framing.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_WHOOP5.md — 50.42.1.0 service, format 1, distinct handshake.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_TRANSPORT.md — frame validation and durable history boundary.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_SENSORS.md — type 40, historical v24/v25, R18 limits.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_COMMANDS.md — version-specific read contracts and negative space.
- https://www.bluetooth.com/specifications/specs/heart-rate-service-1-0/ — standard Heart Rate Service.

Licence source: [Noop LICENSE](https://github.com/ryanbr/noop/blob/main/LICENSE); upstream credits: [Noop ATTRIBUTION](https://github.com/ryanbr/noop/blob/main/ATTRIBUTION.md).

Noop credits johnmiddleton12/my-whoop for Whoop 4 and b-nnett/goose for Whoop 5. Tempo is an original codebase, not a fork. No source implementation or prose from Noop has been copied. Noop's original code/documentation uses PolyForm Noncommercial 1.0.0 (Copyright 2026 NoopApp). Its licence explicitly excludes factual wire identifiers/layouts/CRC parameters from copyright claims. Tempo reuses those interoperability facts and independently implements parsers. Any future copying requires separate licence assessment and notices; the existing Tempo licence does not relicense third-party material.

## Implemented facts

Standard path (both): service 180D, characteristic 2A37. Flags select HR width, contact support/status, energy field and RR words in 1/1024 s. Receipt timestamps are phone UTC instants; the HRS packet has no device timestamp. Device Information service 180A exposes firmware 2A26 and, where available, serial 2A25. Serial identity is hashed and never routinely logged. A Whoop 4 DIS firmware value may describe the Bluetooth processor rather than the application firmware; it must not unlock proprietary history.

Whoop 4: service 61080001-8d6d-82b8-614a-1c8cb0f8dcc6, command 0002, notifications 0003/0004/0005. Envelope AA, u16le declared length, CRC8 length bytes (poly07), inner offset4, CRC32 at declared length, full size length+4. Reflected CRC32 EDB88320 with initial/final FFFFFFFF. Type40 maps HR at12, RR count13 and ms words14; device seconds6, unresolved fraction10. History type47/v24 maps seconds11, HR21, RR count22, words23; raw optical/thermal/respiratory fields are not calibrated physiological values. v25 is a separate84-byte layout with no mapped per-second HR. Unknown layout is rejected, never interpreted as v24.

Whoop 5: service fd4b0001-cce1-4033-93ce-002d5875f58a, command0002, notifications0003/0004/0005/0007. Format1 has AA01, u16le complete-minus8, CRC16-Modbus over bytes0–5 (A001/FFFF), inner offset8, body padded to four bytes, CRC32 over padded inner. Type40 seconds10, HR16, RR count17 and tick words18; fraction14 unresolved. The documented fixed hello is tested solely as an envelope arithmetic example; it is not sent by the production transport. R18 temperature/quality meanings and historical negotiation have not been enabled.

## Historical boundary

Public evidence shows Whoop 4 41.17.6.0 can emit v24 or v25. The former supports some overnight inputs; the latter must not be used to invent HR. Whoop 5 live HR has public hardware reports, while deeper overnight input availability remains incomplete. Firmware50.42.1.0 documentation is not equivalent to runtime validation on an owned band.

Command22/body00 starts Whoop4 offload in observed captures. END acknowledgement23/body01+opaque8-byte token can permit reclamation. Tempo now implements ordinary WHOOP4 chunk receipt acknowledgements as part of the explicitly requested history retrieval. They are emitted only after decoded observations, all raw chunk frames and the original cursor token commit atomically. This normal transfer can let the band reclaim copied history; it is not a forced erase/trim command. Forced trim, reset and destructive control commands remain excluded. WHOOP4 transfer is experimental and requires physical validation; WHOOP5 transfer remains unavailable pending its distinct initialization/metadata contract and owned-band evidence. There is no history retention-duration guarantee.

No firmware flashing, reboot/power-down, trim/delete, certificate transfer, authentication bypass, sensor-enable probing or cloud service authentication is implemented.

## Body placement boundary

The public command reference reviewed for this update does not establish a validated wearing-location read/write contract implemented in Tempo. Standard HR/contact notifications do not identify wrist, bicep or underwear. Tempo therefore stores manual placement reports independently of the BLE adapter and sends no placement command. [WearingPlacement.md](WearingPlacement.md) documents official placement-sensitive feature evidence and the limits of the original analytics.

## Wear-status reassessment — 2026-10-12

Rechecked [current command reference](https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_COMMANDS.md) without copying implementation. Command84 is documented for Whoop4 41.17.6.0 and Whoop5/MG50.42.1.0. The latter revision1 cached-status reply is four bytes: revision, fixed zero, fixed255, then on-body0/1. The middle fields are placeholders, not measured location/confidence. Outer success/result validation matters: failure can carry an initialized body. The Whoop4 legacy reply contract is different and is not supplied an interchangeable Whoop5 decoder. Command148 forces worn state and disables detection; it is excluded from Tempo.

These facts do not enable a safe production path by themselves. Tempo currently uses standard HRS contact flags, not a proprietary link/firmware-bound body query. GenericHR reception establishes neither the encrypted proprietary link nor the application firmware identity. Until the relevant adapter/link/result/firmware paths and physical wear interpretation are validated, unknown stays unknown internally and the UI says Wear not reported. No speculative Bluetooth writes were added in this refinement.

## Optional standard battery report

Tempo reads a single discovered Battery Service (180F), Battery Level (2A19), using the Bluetooth SIG contract: exactly one UINT8 byte, 0–100 percent. It subscribes only when notification is exposed and limits additional reads to once per 15 minutes per connected device, including foreground/manual refresh. Multiple Battery Service instances are ignored until their identities are established. No vendor battery command is invented or sent.

The top control shows a reported percentage only for the selected connected source, outside demo, with a reading no older than one hour. Missing, malformed, stale or disconnected reports leave the percentage hidden. Band status discloses timestamp, stale state and unverified accuracy. The cache is phone-local and not synced as physiological history. An exposed standard service does not prove accuracy: community evidence has warned of constant100 reports on some firmware. Compare against a trusted device reading on both owned bands before relying on it; firmware-specific battery querying remains unavailable.

Evidence: [SIG assigned numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html), [Battery Service1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/BAS_v1.1/out/en/index-en.html). Parser and display gates are software-verified; actual WHOOP service exposure and accuracy remain physical gate E01.

## Retention reassessment — 2026-10-12

A [WHOOP Community support reply](https://www.community.whoop.com/t/whopp-did-not-sync-my-data/7547) states up to14 days of on-device storage, without specifying firmware or a byte capacity. This is a manufacturer-service retention statement, not proof that Tempo can retrieve14 days. Current protocol reference distinguishes WHOOP4 and5 history, and public release notes still report WHOOP5 history limitations. No uniform retention guarantee or exact flash capacity is established for Tempo. Owner-reported live gaps prioritise catch-up work (C05); neither wear nor current HR proves continuous phone receipt.
