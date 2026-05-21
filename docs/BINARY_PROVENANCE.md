# Binary provenance

This repository includes binary artifacts captured from a Samsung Galaxy J7 Prime SM-G610F / on7xelte Android 7.0 system image and recovery-side helper binaries built during the investigation.

## Important

The included Samsung vold binary is not original project code. It is preserved only so the exact recovery experiment can be reproduced in a private research context.

Do not run included binaries blindly. Verify firmware build, hashes, target architecture, and patch offsets before using them on any device.

## Relevant binaries

- binaries/vold: stock Samsung vold pulled from the target firmware/device.
- binaries/vold_patched: patched copy of stock Samsung vold.
- binaries/run_vold_patched_with_sockets.arm64: ARM64 helper used to recreate Android init socket state and exec patched vold.
