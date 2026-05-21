# Binary provenance

The original private research bundle contained stock Samsung binaries and a patched copy of Samsung `vold` captured from the target device/firmware.

Those binaries are intentionally not included in the public repository.

## Why binaries are excluded

- Stock Samsung `vold` is proprietary Samsung firmware content.
- A prebuilt patched `vold` is not trustworthy as a public artifact without independent verification.
- Public users should reproduce analysis from their own firmware image and verify offsets, hashes, architecture, and control flow themselves.

## What is documented instead

This repository keeps:

- the observed patch offset and byte change
- the purpose of the patch
- the recovery environment reconstruction method
- the socket-wrapper source
- scripts and research notes

## Private artifact names

Private bundle artifacts were:

- `vold`: stock Samsung vold from the tested device/firmware
- `vold_patched`: patched copy used during testing
- `run_vold_patched_with_sockets.arm64`: compiled helper binary

Only source and documentation should be used for public review.
