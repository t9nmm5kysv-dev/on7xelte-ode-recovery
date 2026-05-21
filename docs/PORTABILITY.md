# Portability and device applicability

## Validated device

This research was validated on:

    Device: Samsung Galaxy J7 Prime
    Model: SM-G610F
    Codename: on7xelte
    Android: 7.0
    Build: NRD90M.G610FDDU1BQHA

This repository should not be read as proof that the same patch or workflow works unchanged on other Samsung devices.

## What may generalize

The general method may apply to other Samsung Android 6/7-era devices that use a similar Samsung ODE/FMP and KeyMaster full-disk encryption stack.

The portable idea is not the exact binary patch. The portable idea is:

    recreate Samsung stock userspace crypto dependencies inside recovery
    recreate Android init socket state for vold
    provide compatible fs_mgr fstab files
    run stock Samsung cryptfs through vdc
    patch recovery-incompatible vold state checks only when needed
    verify ODE/KeyMaster execution through logs

## What is device-specific

The following are device/build-specific and must not be blindly reused:

    vold binary
    vold patch offset
    patched instruction bytes
    fstab block devices
    vendor library paths
    secure-storage behavior
    KeyMaster/TEE behavior
    partition layout
    recovery environment

For this device, the observed vold patch was:

    offset: 0x59edc
    old bytes: 28 b9
    new bytes: 1a e0

That offset is not expected to be stable across firmware builds or devices.

## Evidence levels

Use these levels when evaluating another device.

### Level 0: Not applicable

The device does not use Samsung ODE/FMP-style full-disk encryption, or it uses a substantially different Android encryption design.

### Level 1: Static firmware indicators match

Firmware inspection shows similar indicators, such as:

    /system/bin/vold
    /system/bin/vdc
    /system/bin/secure_storage_daemon
    /system/vendor/lib/libsecure_storage.so
    /system/vendor/lib/libMcRegistry.so
    /system/vendor/lib/libtlc_comm.so
    /system/vendor/lib/libtlc_tz_ccm.so
    ODE/FMP strings in footer or vold
    forceencrypt=footer or encryptable=footer fstab behavior

This level suggests possible applicability, but proves nothing at runtime.

### Level 2: Stock vold can run in recovery

The stock Samsung vold stack starts inside recovery after recreating:

    /vendor
    secure-storage socket
    /dev/socket/vold
    /dev/socket/cryptd
    ANDROID_SOCKET_* variables
    fstab aliases
    vold command-line context arguments

This proves the userspace environment can be partially reconstructed.

### Level 3: vdc reaches cryptfs_check_passwd

vdc cryptfs checkpw reaches Samsung cryptfs instead of failing with missing sockets, missing libraries, or missing fstab.

### Level 4: ODE/KeyMaster rejection is observed

Wrong credentials produce logs like:

    CryptfsODE: Verifying pass with custom
    ODE_KeyManager: Use KeyMaster
    ODE_KeyManagerKeyMaster: obtainKey
    AES_256_GCM_Decrypt Fail
    CryptfsODE: Failed to decrypt master key
    Cryptfs: Password did not match

This proves the candidate is being tested through Samsung ODE/KeyMaster.

### Level 5: Successful decryption

A known-correct credential creates a dm device and allows /data/media/0 to be mounted read-only.

    /dev/block/dm-*
    /data/media/0 visible

This is the only level that proves practical recovery works on that device.

## Current portability claim

Current claim:

    Validated only on SM-G610F / on7xelte Android 7.0.
    Likely relevant to closely related Samsung Android 6/7 ODE/FMP devices.
    Not proven on other devices.

Any broader claim requires additional device testing or at least firmware-level static analysis plus runtime logs from other models.
