# Samsung Galaxy J7 Prime (`on7xelte`) ODE Recovery Research

This repository documents a recovery-side investigation into Samsung Android 7.0 ODE/FMP encryption on the Galaxy J7 Prime (`SM-G610F`, `on7xelte`). The goal was to understand why TWRP could not decrypt `/data`, reproduce Samsung’s stock decryption path inside recovery, and preserve the scripts, binaries, logs, and candidate-generation work used during the investigation.

This is not a generic unlock or bypass project. The work reconstructs Samsung’s stock ODE/KeyMaster credential-verification path from TWRP recovery. The correct disk credential is still required.

---

## Summary

The device used Samsung ODE/FMP-style full-disk encryption. Standard TWRP decryption failed. Patching TWRP’s `recovery.fstab` was not enough. Legacy Android FDE extraction tools were also not applicable.

The successful technical path was:

1. Mount stock `/system` from TWRP.
2. Recreate Samsung vendor paths and secure-storage support.
3. Start Samsung `secure_storage_daemon`.
4. Recreate Android `init` sockets expected by stock `vold`.
5. Recreate the expected fs_mgr fstab files.
6. Patch stock Samsung `vold` to skip a recovery-incompatible runtime-state guard.
7. Run patched `vold` from recovery.
8. Use `vdc cryptfs checkpw <candidate>` to reach Samsung ODE and KeyMaster.

After this, failed candidates produced real Samsung ODE/KeyMaster failures:

```text
CryptfsODE: Verifying pass with custom
ODE_KeyManager: Use KeyMaster
ODE_KeyManagerKeyMaster: obtainKey
AES_256_GCM_Decrypt Fail
CryptfsODE: Failed to decrypt master key
Cryptfs: Password did not match
```

That proves the recovery-side technical blocker was solved. Remaining failures are credential failures, not TWRP or fstab failures.

---

## Device

```text
Model: SM-G610F
Codename: on7xelte
Android: 7.0
Build: NRD90M.G610FDDU1BQHA
Security patch: 2017-08-01
```

Observed partition mapping:

```text
/system  -> /dev/block/mmcblk0p21
/cache   -> /dev/block/mmcblk0p22
/data    -> /dev/block/mmcblk0p25
/efs     -> /dev/block/mmcblk0p3
```

---

## Repository layout

```text
.
├── README.md
├── MANIFEST.md
├── notes/
│   ├── on7xelte_ode_recovery_research_paper.md
│   └── samsung_j7_ode_twrp_recovery_notes.md
├── binaries/
│   ├── vold
│   ├── vold_patched
│   └── run_vold_patched_with_sockets.arm64
├── scripts/
│   ├── run_vold_patched_with_sockets.c
│   ├── device_try_passwords.sh
│   ├── start_local_decrypt.sh
│   ├── run_all.sh
│   ├── try_password_file_decrypt.sh
│   ├── try_password_file_fast.sh
│   └── fstab.raw
├── generators/
│   ├── gen_simple_letter_number_candidates.py
│   ├── gen_pattern_candidates.py
│   └── gen_sequence_repetitive_candidates.py
├── candidates/
│   └── generated candidate lists
├── logs/
│   ├── ode_keymaster_tail.txt
│   ├── live_keymaster_counter_proof.txt
│   ├── phone_processes.txt
│   ├── dm_mapper_state.txt
│   └── data_media_check.txt
└── phone_cache/
    └── decrypt_work/
```

---

## Key findings

### 1. Legacy Android FDE tools did not apply

`androidfde2john.py` failed because the device did not use the old Android <=4.3 `aes256/cbc-essiv:sha256` footer format. The target used Samsung ODE/FMP and KeyMaster.

### 2. Older TWRP images were unreliable

Several old TWRP images used an incorrect userdata partition such as `mmcblk0p24`, while the target device used `mmcblk0p25`. Some older recoveries also had boot or touchscreen issues.

### 3. TWRP fstab patching was insufficient

Patching the working TWRP 3.7.1 fstab to remove `fileencryption=ice` and adjust footer length allowed the image to boot, but TWRP still failed to decrypt. The missing component was Samsung’s stock ODE/KeyMaster cryptfs path.

### 4. Stock Samsung `vold` required Android init state

Directly running stock `vold` failed because recovery lacked:

```text
/vendor
Samsung secure-storage daemon
/dev/.secure_storage/ssd_socket
/dev/socket/vold
/dev/socket/cryptd
ANDROID_SOCKET_* variables
stock vold.rc arguments
valid /fstab aliases
```

These had to be recreated manually.

### 5. Stock `vold` had a recovery-incompatible crypto-state guard

Even after recreating the environment, stock `vold` refused to proceed:

```text
encrypted fs already validated or not running with encryption, aborting
```

A two-byte patch changed the branch at offset `0x59edc`:

```text
old: 28 b9
new: 1a e0
```

This allowed `cryptfs_check_passwd` to continue into footer and KeyMaster handling.

### 6. The patched path reached Samsung ODE and KeyMaster

Logs confirmed:

```text
CryptfsODE
Use KeyMaster
obtainKey
AES_256_GCM_Decrypt
Failed to decrypt master key
Password did not match
```

This is the central technical result.

---

## Important files

### Binaries

```text
binaries/vold
binaries/vold_patched
binaries/run_vold_patched_with_sockets.arm64
```

### Source/scripts

```text
scripts/run_vold_patched_with_sockets.c
scripts/device_try_passwords.sh
scripts/start_local_decrypt.sh
scripts/run_all.sh
scripts/fstab.raw
```

### Research notes

```text
notes/on7xelte_ode_recovery_research_paper.md
notes/samsung_j7_ode_twrp_recovery_notes.md
```

### Proof logs

```text
logs/ode_keymaster_tail.txt
logs/live_keymaster_counter_proof.txt
```

---

## Reproduction outline

From TWRP recovery:

1. Ensure `/system` can be mounted.
2. Place runtime files under `/cache/decrypt_work`.
3. Run:

```sh
/cache/decrypt_work/run_all.sh
```

The launcher prepares the environment, starts Samsung secure storage, starts patched `vold`, and begins candidate verification.

To verify ODE/KeyMaster activity:

```sh
adb shell 'logcat -d | grep -iE "CryptfsODE|KeyMaster|obtainKey|AES_256_GCM|Password did not match" | tail -80'
```

To verify active progress:

```sh
adb shell 'logcat -d | grep -i "Failed to decrypt master key" | tail -3'
sleep 10
adb shell 'logcat -d | grep -i "Failed to decrypt master key" | tail -3'
```

If `count=` increases, candidates are being tested through Samsung ODE/KeyMaster.

---

## Success condition

A successful credential should cause a dm device to appear:

```text
/dev/block/dm-*
```

Then mount read-only:

```sh
mkdir -p /data
mount -t ext4 -o ro /dev/block/dm-0 /data
ls -la /data/media/0
```

Then pull recovered user data:

```sh
adb pull /data/media/0 ./phone_recovered/
```

---

## Safety notes

Do not run:

```text
cryptfs enablecrypto
cryptfs erase_footer
format /data
wipe /data
repair encrypted userdata as ext4 before decryption
mount decrypted data read-write before recovery
```

The safe post-success mount is read-only:

```sh
mount -t ext4 -o ro /dev/block/dm-0 /data
```

---

## Conclusion

The investigation showed that the Galaxy J7 Prime’s encrypted userdata could not be decrypted by TWRP alone because the real Samsung ODE/FMP/KeyMaster path was missing. By recreating Samsung userspace dependencies and patching a stock `vold` runtime guard, recovery-side credential verification was made to reach Samsung ODE and KeyMaster successfully.

The method does not bypass the encryption credential. It makes the correct Samsung decryption path available from TWRP recovery. Actual data recovery still requires the correct original disk decryption password.
