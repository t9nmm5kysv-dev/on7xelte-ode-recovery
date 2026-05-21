# Samsung Galaxy J7 Prime (`on7xelte`) ODE Recovery Research

**Researcher:** Omer Semsi (`@t9nmm5kysv-dev`)

This repository documents recovery-side research on Samsung Android 7.0 ODE/FMP encryption behavior on the Galaxy J7 Prime (`SM-G610F`, `on7xelte`).

The work investigates why standard TWRP decryption failed and how Samsung's stock ODE/KeyMaster credential-verification path can be reconstructed from recovery.

This is not a generic unlock project. It does not bypass encryption, defeat KeyMaster, extract disk keys, or recover data without the correct disk credential.

---

## Validated target

    Device: Samsung Galaxy J7 Prime
    Model: SM-G610F
    Codename: on7xelte
    Android: 7.0
    Build: NRD90M.G610FDDU1BQHA

This repository is validated only for the documented target. Other Samsung devices require separate firmware analysis and runtime verification.

See `docs/PORTABILITY.md`.

---

## Core finding

TWRP failed because the required Samsung stock ODE/FMP and KeyMaster path was missing from the recovery environment. The issue was not solved by fstab patching alone.

The successful technical path was:

1. Mount stock `/system` from recovery.
2. Recreate Samsung vendor paths.
3. Start Samsung secure-storage support.
4. Recreate Android `init` sockets expected by stock `vold`.
5. Provide compatible fs_mgr fstab aliases.
6. Run stock Samsung cryptfs through `vdc`.
7. Patch a recovery-incompatible `vold` runtime-state guard when required.
8. Verify Samsung ODE/KeyMaster execution through logs.

Representative wrong-credential behavior:

    CryptfsODE: Verifying pass with custom
    ODE_KeyManager: Use KeyMaster
    ODE_KeyManagerKeyMaster: obtainKey
    AES_256_GCM_Decrypt Fail
    CryptfsODE: Failed to decrypt master key
    Cryptfs: Password did not match

That log pattern proves the candidate reached Samsung ODE/KeyMaster verification. It does not prove credential recovery.

---

## Public repository scope

This public repository intentionally excludes:

- Samsung proprietary binaries
- patched Samsung binaries
- generated password candidate lists
- phone-side cache dumps
- raw recovery working directories
- recovered data
- found credentials

The original private research bundle contained additional runtime artifacts. They are excluded here because they are either proprietary, sensitive, noisy, or not suitable for a public repository.

See `docs/PUBLIC_SCOPE.md` and `docs/BINARY_PROVENANCE.md`.

---

## Repository layout

    README.md
    MANIFEST.md
    LICENSE
    docs/
      BINARY_PROVENANCE.md
      EVIDENCE_LOGS.md
      PORTABILITY.md
      PUBLIC_SCOPE.md
      REPRODUCIBILITY.md
      THREAT_MODEL.md
      VOLD_PATCH.md
      PUBLIC_HASHES.txt
    notes/
      on7xelte_ode_recovery_research_paper.md
      samsung_j7_ode_twrp_recovery_notes.md
    scripts/
      run_vold_patched_with_sockets.c
      device_try_passwords.sh
      start_local_decrypt.sh
      run_all.sh
      try_password_file_decrypt.sh
      try_password_file_fast.sh
      fstab.raw
    generators/
      gen_simple_letter_number_candidates.py
      gen_pattern_candidates.py
      gen_sequence_repetitive_candidates.py

---

## Documentation

Start here:

- `notes/on7xelte_ode_recovery_research_paper.md` - full research write-up
- `docs/THREAT_MODEL.md` - security impact and limitations
- `docs/PORTABILITY.md` - device applicability and evidence levels
- `docs/VOLD_PATCH.md` - documented `vold` patch behavior
- `docs/BINARY_PROVENANCE.md` - why binaries are excluded
- `docs/REPRODUCIBILITY.md` - how to reproduce from your own firmware
- `docs/EVIDENCE_LOGS.md` - sanitized evidence log excerpts

---

## Security impact

This work enables recovery-side automation of credential verification through Samsung's original ODE/KeyMaster path.

It does not:

- bypass encryption
- extract disk keys
- defeat KeyMaster
- recover data without the correct credential
- provide GPU/hashcat-style offline cracking
- enable remote attacks

The practical attack surface requires physical access, a bootable custom recovery environment, compatible Samsung stock userspace components, device/build-specific patching, and weak or guessable credentials.

Measured attempt speed on the tested device was roughly 0.66-0.70 seconds per candidate. Strong alphanumeric credentials remain impractical to brute force through this method.

---

## Reproducibility

Do not use prebuilt Samsung binaries from random sources.

A responsible reproduction should:

1. Extract stock firmware for the exact target build.
2. Pull or extract that build's own `vold`, `vdc`, vendor libraries, and fstab.
3. Verify architecture and hashes.
4. Recreate the recovery runtime environment.
5. Locate equivalent control flow in that build's `vold`.
6. Validate through logs that ODE/KeyMaster is reached.
7. Treat every patch offset as build-specific.

See `docs/REPRODUCIBILITY.md`.

---

## Status

The method was validated to Level 4 in the evidence model defined in `docs/PORTABILITY.md`: wrong credentials reached Samsung ODE/KeyMaster and were rejected by the real master-key verification path.

Level 5 would require a known-correct credential producing a dm device and visible `/data/media/0`.

---

## License

Original scripts and documentation in this repository are released under the MIT License.

This license does not apply to Samsung firmware, Samsung binaries, or any proprietary third-party code. Those artifacts are intentionally excluded from the public repository.
