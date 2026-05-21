# Samsung J7 Prime / on7xelte TWRP ODE Decryption Recovery Notes

## 0. Scope

This file documents the recovery work done on a Samsung Galaxy J7 Prime / `on7xelte` where TWRP booted but could not decrypt `/data`.

The goal was not to bypass the user credential. The goal was to make the stock Samsung crypto stack run far enough inside TWRP recovery to reach Samsung ODE and KeyMaster. Once that happened, KeyMaster could test real password candidates.

Final technical status:

- TWRP booted reliably with the known-good TWRP 3.7.1 image.
- TWRP's own decrypt path failed.
- Stock Samsung `/system/bin/vold` was mounted/extracted from the stock system partition.
- Samsung secure-storage userspace was started manually.
- Stock `vold` was launched manually with Android-init-style sockets.
- `/fstab` aliases were recreated for stock `vold`/`fs_mgr`.
- A small local patch was applied to a copy of `vold` so it skipped the recovery-only crypto-state guard.
- Patched `vold` reached Samsung ODE + KeyMaster.
- Password candidates were genuinely tested against the encrypted master key.
- Tested candidates were rejected with `Password did not match`.

Do not run `enablecrypto`. Do not run `erase_footer`. Do not wipe or format `/data`.

---

## 1. Device and recovery facts

Device seen from TWRP:

```text
product: omni_on7xelte
model: Samsung_Galaxy_J7_Prime
device: on7xelte
TWRP/Omni display id: omni_on7xelte-eng 16.1.0 PQ2A.190405.003 eng.batuha.20240301.221444 test-keys
```

Working recovery image:

```text
TWRP-3.7.1-on7xelte-@Batuhantrkgl.img
```

Working recovery `/data` line before any patching:

```text
/data ext4 /dev/block/platform/13540000.dwmmc0/by-name/USERDATA flags=display="Data";encryptable=footer;length=-20480;fileencryption=ice
```

Stock Android system properties from the stock `/system` partition:

```text
ro.build.display.id=NRD90M.G610FDDU1BQHA
ro.build.version.release=7.0
ro.build.version.security_patch=2017-08-01
ro.product.model=SM-G610F
ro.product.device=on7xelte
ro.build.fingerprint=samsung/on7xeltedd/on7xelte:7.0/NRD90M/G610FDDU1BQHA:user/release-keys
```

Footer evidence from the userdata footer:

```text
aes-xts-fmp
security.ode.trustedboot
pass
security.ode.ext_migrate
```

That showed the device used Samsung ODE/FMP style full-disk encryption, not simple old generic Android FDE.

---

## 2. Failed or discarded approaches

### 2.1 TWRP fstab patching

We tried modifying TWRP's `recovery.fstab`:

```text
remove ;fileencryption=ice
change length=-20480 to length=-16384
```

A byte-preserving patch allowed TWRP to boot with the modified fstab, but decryption still failed:

```text
twrp decrypt default_password
Failed to decrypt data.
```

Conclusion: TWRP's decrypt implementation did not properly handle this Samsung ODE/KeyMaster/FMP path.

### 2.2 Older TWRP images

Older TWRP images were inspected. Several pointed `/data` to older block numbers like `mmcblk0p24`, while this device's userdata was `mmcblk0p25`.

Patching/repacking older recoveries caused boot hangs or touchscreen problems. That route was abandoned.

### 2.3 `androidfde2john`

Kali's `androidfde2john.py` was tested but rejected the image/footer:

```text
Note: This script only works for old Android <= 4.3 disk images and only aes256/cbc-essiv:sha256 images are supported!
Cannot read disk image footer
```

Conclusion: not useful for Samsung Android 7 ODE/FMP encryption.

### 2.4 Stock `vold` without Samsung environment

Running stock `/system/bin/vold` initially failed due to missing vendor libraries:

```text
CANNOT LINK EXECUTABLE "/system/bin/vold": library "libsecure_storage.so" not found
```

After vendor library paths were fixed, `vold` still needed Android init-created sockets and proper `vold.rc` arguments.

---

## 3. Samsung components used

Relevant stock Samsung libraries found:

```text
/system/vendor/lib/libMcRegistry.so
/system/vendor/lib/libsecure_storage.so
/system/vendor/lib/libsecure_storage_jni.so
/system/vendor/lib/libtlc_comm.so
/system/vendor/lib/libtlc_tz_ccm.so
```

Stock `vold` linked against Samsung ODE and KeyMaster-related libraries:

```text
libsec_ode_keymanager.so
libsec_ode_keymanager_utils.so
libsec_ode_pbkdf.so
libsec_ode_sdcardencryption.so
libsecure_storage.so
libkeymaster_messages.so
libsoftkeymaster.so
libsoftkeymasterdevice.so
```

The secure-storage daemon expected:

```text
/vendor/lib/libsecure_storage.so
/dev/.secure_storage/ssd_socket
/data/system/secure_storage/
/system/etc/secure_storage/
/system/app/mcRegistry/*.tlbin
```

We recreated `/vendor` in recovery:

```sh
rm -rf /vendor
ln -s /system/vendor /vendor
```

Starting the secure-storage daemon created:

```text
/dev/.secure_storage/ssd_socket
```

That proved the Samsung helper stack was alive enough for `vold` to use it.

---

## 4. Manually launching stock `vold`

### 4.1 Why a wrapper was needed

Android `init` normally creates sockets before starting `vold`, then passes file descriptors with environment variables:

```text
ANDROID_SOCKET_vold
ANDROID_SOCKET_cryptd
ANDROID_SOCKET_frigate
ANDROID_SOCKET_epm
ANDROID_SOCKET_ppm
ANDROID_SOCKET_dir_enc_report
```

Directly running `/system/bin/vold` from shell did not create those sockets. Then `vdc` failed with:

```text
Error connecting to cryptd: No such file or directory
```

Stock `vold` also needed arguments from `vold.rc`:

```text
--blkid_context=u:r:blkid:s0
--blkid_untrusted_context=u:r:blkid_untrusted:s0
--fsck_context=u:r:fsck:s0
--fsck_untrusted_context=u:r:fsck_untrusted:s0
```

Without those args it crashed with:

```text
Check failed: android::vold::sBlkidContext != nullptr
```

### 4.2 Socket wrapper behavior

The wrapper does four things:

1. Creates Unix sockets under `/dev/socket`.
2. Sets the corresponding `ANDROID_SOCKET_*` environment variables.
3. Sets `LD_LIBRARY_PATH`, `ANDROID_ROOT`, and `ANDROID_DATA`.
4. Execs stock or patched `vold` with the proper `vold.rc` arguments.

The companion script regenerates and pushes this wrapper automatically.

---

## 5. The fstab problem

Stock `vold` initially failed with:

```text
Failed to open default fstab /fstab.
fs_mgr: Cannot open file /fstab.
Cryptfs: Could not get footer
```

The trailing dot was important. Because of `ro.hardware` behavior in recovery, `fs_mgr` looked for `/fstab.`.

We created all likely aliases:

```text
/fstab
/fstab.
/fstab.samsungexynos7870
/fstab.exynos7870
/fstab.on7xelte
```

The raw fstab that worked best:

```text
/dev/block/mmcblk0p21 /system ext4 ro,errors=panic,noload wait
/dev/block/mmcblk0p22 /cache ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check
/dev/block/mmcblk0p25 /data ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check,forceencrypt=footer
/dev/block/mmcblk0p3 /efs ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check
```

---

## 6. Stock `vold` crypto-state guard

Even after sockets, libraries, props, and fstab were correct, stock `vold` refused to enter the real password/footer path:

```text
Cryptfs: encrypted fs already validated or not running with encryption, aborting
Cryptfs: Could not get footer
```

This was not a password failure. It was a runtime state failure caused by running stock `vold` from TWRP instead of Android early boot.

Reverse engineering found the relevant function in stock `vold`:

```text
vold: ELF 32-bit LSB shared object, ARM
string offset: 0x84711 "encrypted fs already validated or not running with encryption, aborting"
xref function: 0x59eb8
```

Relevant disassembly:

```asm
0x00059edc      28b9      cbnz r0, 0x59eea
...
0x00059eea                log "encrypted fs already validated or not running with encryption, aborting"
0x00059efa                return -1
...
0x00059f14      2046      mov r0, r4
0x00059f16                call check_unmounted_and_get_ftr-like helper
```

Patch applied to a local copy only:

```text
old @ 0x59edc: 28 b9    cbnz r0, 0x59eea
new @ 0x59edc: 1a e0    b.n 0x59f14
```

This did not bypass the user password. It only skipped a recovery-state guard and allowed stock Samsung ODE/KeyMaster code to run.

---

## 7. Proof that the patch worked

Before patching, `vold` never reached Samsung ODE validation.

After patching, logs showed:

```text
CryptfsODE: ICD check
ODE_KeyManager: Use KeyMaster
ODE_KeyManagerKeyMaster: obtainKey
AES_256_GCM_Decrypt Fail
CryptfsODE: Failed to decrypt master key
Cryptfs: Error decrypting key for test mount
Cryptfs: Password did not match
```

This proves:

- the patch worked;
- Samsung ODE was reached;
- KeyMaster was reached;
- the supplied candidate was tested;
- the supplied candidate was rejected.

---

## 8. Meaning of failure counters

Logs showed entries like:

```text
Failed to decrypt master key (count=32, rc=-1)
Error decrypting key for test mount(32)
Password did not match
```

Later testing reached counts in the thousands.

Meaning:

- The supplied candidate failed to decrypt the disk master key.
- The counter belongs to Samsung ODE/KeyMaster failure handling.
- It may be session-local or persisted; that was not proven.
- Treat it as risky.
- Do not blindly brute force.

---

## 9. What reboot wipes

A reboot wipes the recovery RAM environment:

```text
/tmp/vold_patched
/tmp/run_vold_patched_with_sockets
/dev/socket/*
/dev/.secure_storage/ssd_socket
/vendor symlink
/fstab aliases
running secure_storage_daemon
running patched vold
```

A reboot does not wipe Kali-side files:

```text
/home/zyxblvxb/Desktop/stock_vold_analysis/vold_patched
/home/zyxblvxb/Desktop/run_vold_patched_with_sockets.arm64
/home/zyxblvxb/Desktop/fstab.raw
backups/images
```

The companion script recreates the volatile recovery environment after reboot.

---

## 10. Companion script usage

Use the companion bash script:

```sh
chmod +x restore_patched_vold_ode_env.sh
./restore_patched_vold_ode_env.sh setup
./restore_patched_vold_ode_env.sh status
./restore_patched_vold_ode_env.sh test-default
./restore_patched_vold_ode_env.sh try-one
./restore_patched_vold_ode_env.sh try-file /home/zyxblvxb/Desktop/password_candidates.txt
```

The script:

1. Mounts `/system`.
2. Recreates `/vendor`.
3. Recreates `/fstab` aliases.
4. Pulls and patches stock `/system/bin/vold` if needed.
5. Builds the socket wrapper if needed.
6. Pushes `/tmp/vold_patched`.
7. Starts `secure_storage_daemon`.
8. Starts patched `vold`.
9. Verifies `/dev/socket/cryptd` and `/dev/.secure_storage/ssd_socket`.
10. Allows controlled password testing.

---

## 11. Things not to do

Do not run:

```text
cryptfs enablecrypto
cryptfs erase_footer
format data
wipe data
repair filesystem on encrypted userdata
mount userdata read-write before decrypting
```

Do not patch `/system/bin/vold` on the phone. Always patch a local copy and run it from `/tmp/vold_patched`.

Do not run random wordlists. The technical path works; the credential is the blocker.

---

## 12. Final conclusion

The recovery-side technical blocker was solved. Patched stock Samsung `vold` runs inside TWRP and reaches Samsung ODE + KeyMaster. The remaining problem is the correct alphanumeric disk credential.
