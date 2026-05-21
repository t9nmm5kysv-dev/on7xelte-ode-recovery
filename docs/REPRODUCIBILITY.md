# Reproducibility guide

This repository does not ship stock Samsung binaries or patched Samsung binaries. A clean reproduction requires extracting device-specific artifacts from the target firmware or device.

## Required inputs

For a comparable Samsung Android 6/7 ODE/FMP device, collect these from the exact target build:

    /system/bin/vold
    /system/bin/vdc
    /system/bin/secure_storage_daemon
    /system/vendor/lib/libsecure_storage.so
    /system/vendor/lib/libMcRegistry.so
    /system/vendor/lib/libtlc_comm.so
    /system/vendor/lib/libtlc_tz_ccm.so
    stock fstab files
    partition map
    recovery environment details

Do not assume that files from one Samsung build are safe or correct for another build.

## Recommended workflow

### 1. Identify the device and build

Record:

    model
    codename
    Android version
    build ID
    security patch level
    partition mapping
    recovery version

### 2. Confirm encryption family

Look for indicators such as:

    ODE strings
    FMP strings
    forceencrypt=footer
    encryptable=footer
    Samsung secure-storage libraries
    KeyMaster usage in logs

If the device uses a substantially different encryption design, this method may not apply.

### 3. Recreate stock userspace dependencies in recovery

The tested workflow required:

    /vendor path pointing to Samsung vendor libraries
    secure_storage_daemon
    /dev/.secure_storage/ssd_socket
    /dev/socket/vold
    /dev/socket/cryptd
    ANDROID_SOCKET_* environment variables
    vold command-line context arguments
    valid fstab aliases

### 4. Analyze stock vold

Search for recovery-incompatible guards around cryptfs password checking. On the validated build, the observed patch was:

    offset: 0x59edc
    old bytes: 28 b9
    new bytes: 1a e0

This offset is build-specific. Do not reuse it blindly.

### 5. Validate runtime behavior

A wrong credential should reach ODE/KeyMaster and produce logs like:

    CryptfsODE: Verifying pass with custom
    ODE_KeyManager: Use KeyMaster
    ODE_KeyManagerKeyMaster: obtainKey
    AES_256_GCM_Decrypt Fail
    CryptfsODE: Failed to decrypt master key
    Cryptfs: Password did not match

If the failure is about missing sockets, missing libraries, missing fstab, or not running with encryption, the runtime environment is still wrong.

### 6. Define evidence level

Use `docs/PORTABILITY.md`.

The validated device reached Level 4:

    ODE/KeyMaster rejection observed

Level 5 requires a known-correct credential and successful dm device creation.

## Public release rules

Do not publish:

    proprietary Samsung binaries
    patched Samsung binaries
    candidate lists
    raw phone cache directories
    found credentials
    recovered user data
