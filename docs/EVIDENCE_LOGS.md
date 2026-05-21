# Evidence log excerpts

These excerpts document that the recovery-side method reached Samsung ODE and KeyMaster. Full raw logs are intentionally not included in the public repository.

## ODE/KeyMaster wrong-credential path

Representative failed credential verification:

    Cryptfs : cryptfs_check_passwd
    CryptfsODE: ICD check (0 / pass)
    CryptfsODE: Verifying pass with custom
    ODE_KeyManager: Use KeyMaster
    ODE_KeyManagerKeyMaster: obtainKey
    ODE_KeyManagerKeyMaster: AES_256_GCM_Decrypt
    ODE_KeyManagerKeyMaster: AES_256_GCM_Decrypt Fail
    CryptfsODE: Failed to decrypt master key
    Cryptfs : Password did not match

## Live counter proof

During testing, repeated wrong candidates increased the Samsung ODE failed-decrypt counter. This showed that candidate attempts were reaching the actual ODE/KeyMaster verification path rather than failing early in TWRP, fstab handling, socket setup, or library loading.

Representative pattern:

    CryptfsODE: Failed to decrypt master key (count=N, rc=-1)
    CryptfsODE: Failed to decrypt master key (count=N+1, rc=-1)
    CryptfsODE: Failed to decrypt master key (count=N+2, rc=-1)

## Interpretation

These logs prove that:

- patched vold accepted vdc commands
- cryptfs_check_passwd executed
- Samsung ODE code executed
- Samsung KeyMaster was used
- wrong candidates were rejected by the real encrypted master-key path

They do not prove credential recovery.
