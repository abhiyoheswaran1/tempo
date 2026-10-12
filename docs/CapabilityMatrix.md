# Runtime capability matrix

`Sources/TempoCore/Capabilities.swift` is the executable policy. Unknown firmware never inherits a proprietary layout. Verified means instance evidence, experimental means public contract or observation without Tempo hardware validation, unsupported means deliberately unavailable in the current adapter, unknown means unresolved. Sensor presence is not capability.

| Capability | Whoop 4 / 41.17.6.0 public evidence | Whoop 5 / 50.42.1.0 public evidence | Enabled Tempo production path |
|---|---|---|---|
| Live HR | Experimental until owned-band test | Experimental until owned-band test | Standard HRS if discovered |
| RR | Experimental; ms proprietary and SIG ticks distinct | Experimental; SIG/proprietary ticks | SIG RR only when packet includes it |
| History | Experimental v24 and separate v25 | Experimental/version dependent | Decoder/cursor API; full retrieval disabled |
| Motion | Experimental raw layouts | Experimental R21/streams | Disabled |
| Verified wear | Experimental retained contact interpretations | Unknown/incomplete | SIG contact flag when supplied; hardware behavior unverified |
| Battery | Experimental proprietary reading; SIG may always say100 | Experimental proprietary response | Unavailable pending instance validation |
| Temperature | Unsupported calibrated value from raw ADC | Experimental R18 on some firmware | Unavailable |
| Respiration | Unsupported calibrated value from raw fields | Unsupported valid rate | Unavailable |
| SpO2 | Unsupported calibrated percentage | Unsupported offline calibrated percentage | Unavailable |
| Haptics | Experimental version-specific controls | Experimental distinct pattern commands | Hidden pending physical effect validation |
| Firmware alarm | Experimental storage/readback/physical effect separate | Experimental firmware-specific | Hidden pending persistence/wake test |
| Identity | Experimental Harvard serial contract | Experimental DIS serial | Hash DIS serial on Whoop5; unresolved Whoop4 |
| Firmware | Processor-specific | Version baseline must be identified | Read DIS if exposed, preserve unknown otherwise |

For any other firmware, proprietary fields remain unknown. Standard services remain experimental until actually discovered. A successfully parsed packet proves software parsing only. A successful write would prove neither wear nor haptic motor operation. Future promotion requires a dated validation entry with generation, firmware and procedure results.

Registered devices, connected peripherals and selected measurement source are distinct. The production transport maintains one connection at a time. Pure state-machine tests do not prove concurrent band connectivity or wear-based switching on hardware.
