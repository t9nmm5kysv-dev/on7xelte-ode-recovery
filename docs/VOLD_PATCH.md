# vold patch note

The patched vold binary changes a recovery-incompatible runtime-state guard so Samsung cryptfs_check_passwd can proceed into the footer and KeyMaster path from TWRP recovery.

## Patch

Observed branch site:

    offset: 0x59edc
    old bytes: 28 b9
    new bytes: 1a e0

## Meaning

The patch does not bypass the disk credential, extract the disk key, defeat KeyMaster, or decrypt data by itself.

It only allows stock Samsung cryptfs logic to continue into the same ODE/KeyMaster credential-verification path that would normally be reached during Android's early boot encryption flow.

## Expected wrong-password behavior

    CryptfsODE: Verifying pass with custom
    ODE_KeyManager: Use KeyMaster
    ODE_KeyManagerKeyMaster: obtainKey
    AES_256_GCM_Decrypt Fail
    CryptfsODE: Failed to decrypt master key
    Cryptfs: Password did not match
