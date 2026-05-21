# Recovery-Side Evaluation of Samsung ODE Decryption on the Galaxy J7 Prime (`on7xelte`)

## Abstract

This report documents an investigation into recovering access to an encrypted Samsung Galaxy J7 Prime (`SM-G610F`, codename `on7xelte`) data partition from TWRP recovery. The device used Samsung Android 7.0 stock firmware with Samsung ODE/FMP-style full-disk encryption. Standard TWRP decryption failed, and multiple recovery-level approaches were tested.

The investigation found that the failure was not caused solely by an incorrect TWRP `/data` fstab entry. Instead, the device required Samsung’s stock `cryptfs` path, including stock `vold`, Samsung ODE libraries, secure-storage support, and KeyMaster. A patched stock `vold` binary was ultimately run from TWRP recovery to bypass a recovery-only runtime-state guard and allow real Samsung ODE/KeyMaster password verification. This did not bypass the credential requirement; it only enabled the correct Samsung decryption code path to execute from recovery.

The main conclusion is that the recovery-side technical blocker was reproducibly solved: Samsung ODE and KeyMaster could be reached from TWRP. Remaining failed attempts represented genuine credential rejection by Samsung KeyMaster, not a TWRP, fstab, footer, or library-loading error.

---

## 1. Device and Environment

The target device was a Samsung Galaxy J7 Prime:

```text
Model: SM-G610F
Codename: on7xelte
Stock Android version: 7.0
Build ID: NRD90M.G610FDDU1BQHA
Security patch level: 2017-08-01
Stock fingerprint:
samsung/on7xeltedd/on7xelte:7.0/NRD90M/G610FDDU1BQHA:user/release-keys
```

The working recovery environment was TWRP/Omni-based:

```text
product: omni_on7xelte
model: Samsung_Galaxy_J7_Prime
device: on7xelte
display id: omni_on7xelte-eng 16.1.0 PQ2A.190405.003 eng.batuha.20240301.221444 test-keys
```

Observed partition mapping:

```text
/system  -> /dev/block/mmcblk0p21
/cache   -> /dev/block/mmcblk0p22
/data    -> /dev/block/mmcblk0p25
/efs     -> /dev/block/mmcblk0p3
```

The userdata encryption footer contained Samsung ODE/FMP-related strings such as:

```text
aes-xts-fmp
security.ode.trustedboot
security.ode.ext_migrate
pass
```

This indicated that the device was not using the simple legacy Android FDE format supported by old `androidfde2john` workflows. It required Samsung’s ODE/FMP/KeyMaster decryption path.

---

## 2. Initial Problem

TWRP booted successfully, but it could not decrypt `/data`. The working TWRP fstab exposed a `/data` entry similar to:

```text
/data ext4 /dev/block/platform/13540000.dwmmc0/by-name/USERDATA flags=display="Data";encryptable=footer;length=-20480;fileencryption=ice
```

This entry was suspicious for two reasons.

First, the device used block-based Samsung ODE/FMP encryption, not ordinary file-based encryption. Second, the `fileencryption=ice` flag looked inappropriate for the stock Android 7.0 Samsung FDE path. Initial assumptions focused on fstab mismatch, footer length, and incorrect recovery configuration.

Those assumptions were only partially correct. Fstab changes alone did not restore decryption.

---

## 3. Research Questions

The investigation centered on four questions:

1. Could the encryption footer be extracted and cracked using existing Android FDE tools?
2. Could an older or differently configured TWRP decrypt the data partition?
3. Could TWRP’s fstab be patched to make decryption work?
4. If TWRP could not decrypt directly, could the stock Samsung userspace decryption stack be reproduced inside TWRP recovery?

The fourth question became the successful line of investigation.

---

## 4. Methods Attempted

### 4.1 Legacy Android FDE Hash Extraction

The tool `androidfde2john.py` was tested against the userdata image and footer:

```text
python3 /usr/share/john/androidfde2john.py phone_data.img crypt_footer.bin
```

The result was:

```text
Note: This script only works for old Android <= 4.3 disk images and only aes256/cbc-essiv:sha256 images are supported.
Cannot read disk image footer.
```

This failure was expected after inspecting the footer. The device did not use the old Android <= 4.3 `aes256/cbc-essiv:sha256` encryption format. It used Samsung ODE/FMP and KeyMaster-assisted decryption.

Conclusion:

```text
Legacy Android FDE hash extraction was not applicable.
```

---

### 4.2 Older TWRP Images

Older `on7xelte` TWRP images were downloaded and inspected. Their ramdisks were unpacked to inspect `recovery.fstab`.

Several older TWRP 3.2.x images had `/data` configured as:

```text
/data ext4 /dev/block/mmcblk0p24 flags=encryptable=footer;length=-20480
```

However, the actual device userdata partition was `mmcblk0p25`. This made those recoveries structurally incorrect for the target device.

An older TWRP 3.0.3-0 image booted but had a nonfunctional touchscreen. A patched TWRP 3.2.3 image either failed to boot or hung after repacking. Repacking itself became a risk because small fstab changes could still alter image layout, compression, or boot expectations.

Conclusion:

```text
Older TWRP images were not reliable. Some had incorrect userdata block mappings, some had hardware input problems, and patched repacks could hang.
```

---

### 4.3 TWRP 3.7.1 Fstab Patching

The working TWRP 3.7.1 image was unpacked. Its `recovery.fstab` was patched by modifying only byte-length-compatible strings where possible.

The original `/data` line contained:

```text
encryptable=footer;length=-20480;fileencryption=ice
```

A byte-preserving patch changed:

```text
;length=-20480       -> ;length=-16384
;fileencryption=ice  -> spaces
```

The patched image booted and showed the modified fstab:

```text
/data ext4 ... flags=display="Data";encryptable=footer;length=-16384
```

However, TWRP still failed to decrypt:

```text
twrp decrypt default_password
Failed to decrypt data.
```

Conclusion:

```text
TWRP fstab correction was insufficient. The missing component was not merely an incorrect /data flag or footer length. TWRP did not execute the required Samsung ODE/KeyMaster stack.
```

---

### 4.4 Running Stock Samsung `vold`

The investigation then shifted toward reproducing Samsung’s stock decryption userspace inside recovery.

Stock `/system/bin/vold` was present after mounting `/system`, but direct execution failed due to missing Samsung vendor libraries:

```text
CANNOT LINK EXECUTABLE "/system/bin/vold": library "libsecure_storage.so" not found
```

Relevant Samsung libraries were found under `/system/vendor/lib`:

```text
/system/vendor/lib/libMcRegistry.so
/system/vendor/lib/libsecure_storage.so
/system/vendor/lib/libsecure_storage_jni.so
/system/vendor/lib/libtlc_comm.so
/system/vendor/lib/libtlc_tz_ccm.so
```

A recovery-side `/vendor` path was created:

```text
/vendor -> /system/vendor
```

The Samsung secure-storage daemon was then started manually. Successful startup was confirmed by creation of:

```text
/dev/.secure_storage/ssd_socket
```

Conclusion:

```text
Samsung secure-storage support could be partially reproduced inside TWRP recovery.
```

---

### 4.5 Android Init Socket Recreation

Stock `vold` normally runs under Android `init`. `init` creates sockets and passes their file descriptors through environment variables such as:

```text
ANDROID_SOCKET_vold
ANDROID_SOCKET_cryptd
ANDROID_SOCKET_frigate
ANDROID_SOCKET_epm
ANDROID_SOCKET_ppm
ANDROID_SOCKET_dir_enc_report
```

Directly running `vold` from a shell did not create these sockets, so `vdc` failed:

```text
Error connecting to cryptd: No such file or directory
```

A static ARM64 wrapper was written. Its purpose was to:

1. Create the required Unix sockets under `/dev/socket`.
2. Set the corresponding `ANDROID_SOCKET_*` environment variables.
3. Set Android runtime variables such as `ANDROID_ROOT` and `ANDROID_DATA`.
4. Execute `vold` with stock-style command-line arguments.

The required `vold` arguments were:

```text
--blkid_context=u:r:blkid:s0
--blkid_untrusted_context=u:r:blkid_untrusted:s0
--fsck_context=u:r:fsck:s0
--fsck_untrusted_context=u:r:fsck_untrusted:s0
```

Without these arguments, stock `vold` could crash because expected context strings were missing.

After adding the wrapper, `vold` and `cryptd` sockets existed:

```text
/dev/socket/vold
/dev/socket/cryptd
```

Conclusion:

```text
The Android init socket environment could be recreated sufficiently for stock vold to accept vdc commands.
```

---

### 4.6 Fstab Recreation

Stock `vold` also expected a default fstab. It attempted to open paths including:

```text
/fstab.
```

Without these fstab files, `cryptfs` could not locate the footer correctly:

```text
Could not get footer
```

The following fstab was created in recovery:

```text
/dev/block/mmcblk0p21 /system ext4 ro,errors=panic,noload wait
/dev/block/mmcblk0p22 /cache ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check
/dev/block/mmcblk0p25 /data ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check,forceencrypt=footer
/dev/block/mmcblk0p3 /efs ext4 nosuid,nodev,noatime,noauto_da_alloc,discard,journal_async_commit,errors=panic wait,check
```

It was copied to several expected names:

```text
/fstab
/fstab.
/fstab.samsungexynos7870
/fstab.exynos7870
/fstab.on7xelte
```

Conclusion:

```text
Stock vold required a valid fs_mgr-style fstab in recovery. Creating fstab aliases resolved one class of footer-read failures.
```

---

## 5. Discovery of the `vold` Runtime-State Guard

Even after solving library paths, secure-storage, sockets, and fstab, stock `vold` still refused to enter the real password-check path:

```text
Cryptfs: encrypted fs already validated or not running with encryption, aborting
Cryptfs: Could not get footer
```

This was a key discovery.

It showed that the failure was not caused by an incorrect password. The code was aborting before real password validation because the stock Android early-boot crypto state had not been established. In normal Android boot, `init`, `fs_mgr`, and `vold` coordinate encryption state before accepting `checkpw`. In TWRP, that state did not exist.

Conclusion:

```text
Stock vold could run in recovery, but an internal cryptfs state guard prevented it from using the footer/password path.
```

---

## 6. Binary Analysis and Patch

Stock `/system/bin/vold` was pulled from the device and identified as:

```text
ELF 32-bit LSB shared object, ARM
```

The string:

```text
encrypted fs already validated or not running with encryption, aborting
```

was found at offset:

```text
0x84711
```

Cross-reference analysis located the relevant function near:

```text
0x59eb8
```

The blocking branch was found at:

```text
0x59edc
```

The relevant control flow was:

```asm
0x00059edc    28 b9    cbnz r0, 0x59eea
...
0x00059eea            log "encrypted fs already validated or not running with encryption"
...
0x00059efa            return -1
...
0x00059f14            continue into footer handling
```

Patch applied:

```text
old bytes at 0x59edc: 28 b9
new bytes at 0x59edc: 1a e0
```

The patched instruction changed the conditional branch into an unconditional branch to continue toward footer handling.

Patch script:

```python
from pathlib import Path

p = Path("vold_patched")
b = bytearray(p.read_bytes())

off = 0x59edc

expected = bytes.fromhex("28b9")
patch = bytes.fromhex("1ae0")

if b[off:off+2] != expected:
    raise SystemExit(
        f"Unexpected bytes at 0x{off:x}: "
        f"{b[off:off+2].hex()} expected {expected.hex()}"
    )

b[off:off+2] = patch
p.write_bytes(b)
```

This patch did not remove credential checking. It only bypassed a runtime-state guard that was inappropriate in recovery.

Conclusion:

```text
A two-byte patch to stock vold allowed Samsung cryptfs to proceed from recovery into the real footer and KeyMaster password verification path.
```

---

## 7. Evidence That Samsung ODE and KeyMaster Were Reached

After running patched `vold`, failed password attempts produced logs such as:

```text
Cryptfs : cryptfs_check_passwd
CryptfsODE: ICD check (0 / pass)
CryptfsODE: Verifying pass with custom
ODE_KeyManager: Use KeyMaster
ODE_KeyManagerKeyMaster: KeyManagerKeyMaster(uint32_t) : Created (10000)
ODE_KeyManagerKeyMaster: obtainKey
ODE_KeyManagerKeyMaster: AES_256_GCM_Decrypt
ODE_KeyManagerKeyMaster: AES_256_GCM_Decrypt Fail
CryptfsODE: Failed to decrypt master key
Cryptfs : Password did not match
```

This proves that:

```text
vdc reached patched vold
patched vold reached cryptfs_check_passwd
Samsung ODE logic executed
Samsung KeyMaster was used
the supplied candidate was tested against the encrypted master key
the candidate failed
```

The important distinction is that `Password did not match` appeared only after the patch. Before the patch, the system failed earlier with “not running with encryption.”

Conclusion:

```text
The recovery environment successfully reached the same Samsung ODE/KeyMaster failure mode expected from a real credential check.
```

---

## 8. Candidate Testing Infrastructure

Once the technical path worked, a candidate-testing script was created. The goal was not to bypass KeyMaster but to automate testing of remembered password variants through the now-working Samsung ODE path.

Two execution modes were used.

### 8.1 Kali-Controlled Mode

Kali-side scripts called:

```text
adb shell vdc cryptfs checkpw <candidate>
```

This worked but was slow due to per-candidate ADB round trips and log checks.

Measured average:

```text
approximately 0.87 seconds per attempt
```

A faster Kali-side mode reduced checks and improved speed to roughly:

```text
approximately 0.69 seconds per attempt
```

### 8.2 Phone-Local Mode

A local phone-side working directory was created:

```text
/cache/decrypt_work
```

Runtime files were pushed there:

```text
vold_patched
run_vold_patched_with_sockets
device_try_passwords.sh
start_local_decrypt.sh
run_all.sh
passwords_seqrep_all.txt
```

Running locally on the phone avoided ADB round trips. However, the bottleneck remained Samsung ODE/KeyMaster itself. Average speed remained approximately:

```text
0.66 to 0.70 seconds per attempt
```

This showed that the bottleneck was not mainly ADB or Bash. It was the Samsung KeyMaster/ODE check.

Conclusion:

```text
Local phone-side execution improved reliability and allowed unplugged operation, but did not dramatically reduce per-attempt time because KeyMaster remained the limiting factor.
```

---

## 9. Candidate Generation Strategy

Early failed candidates included:

```text
632765
622628
620449
yoll.0987
123456
111111
345699
098765
asd12345
11223344
```

The remembered password style suggested:

```text
simple number pattern
at least one letter
possibly a dot
no complex symbols
```

The investigation moved away from broad generic wordlists and toward structured generation.

Generated candidate families included:

1. One letter plus repeated/simple numbers.
2. One letter plus optional dot and repeated/simple numbers.
3. Two repeated letters plus repeated/simple numbers.
4. Ordered sequences from 1 to 9.
5. Reverse ordered sequences from 9 to 1.
6. Zero-prefixed sequences such as `098765`.
7. Repeated blocks such as `111111`.
8. Pair patterns such as `112233`, `11223344`, and `001122`.

The final sequence/repetition generator produced:

```text
passwords_seqrep_tier1.txt   18,424
passwords_seqrep_tier2.txt  195,348
passwords_seqrep_tier3.txt  205,380
passwords_seqrep_all.txt    419,152
```

At approximately 0.66–0.70 seconds per attempt, the combined run was estimated at roughly:

```text
77 to 82 hours
```

Conclusion:

```text
The best candidate strategy was structured expansion from remembered numeric patterns with inserted letters and optional dots, not generic brute-force or public wordlists.
```

---

## 10. Failure Analysis

The following approaches failed or were ruled out:

### Legacy footer cracking failed

Reason:

```text
Samsung Android 7 ODE/FMP encryption is not compatible with old Android <=4.3 androidfde2john assumptions.
```

### TWRP 3.2.x recoveries failed

Reasons:

```text
some used the wrong userdata block partition
some did not boot correctly after repacking
some had hardware input issues
```

### TWRP 3.7.1 fstab-only patch failed

Reason:

```text
TWRP still lacked the Samsung ODE/KeyMaster cryptfs path.
```

### Stock `vold` direct execution failed

Reasons:

```text
missing Samsung vendor libraries
missing /vendor path
missing secure-storage socket
missing init-created vold/cryptd sockets
missing vold.rc arguments
missing default fstab aliases
```

### Stock `vold` with recreated environment still failed

Reason:

```text
cryptfs runtime-state guard refused to proceed because Android early-boot encryption state was absent in recovery.
```

### Patched `vold` worked technically, but candidates failed

Reason:

```text
Samsung KeyMaster genuinely rejected tested credentials.
```

---

## 11. Conclusions

The investigation produced several concrete conclusions.

First, the device did not use a legacy Android FDE format that could be extracted and cracked with standard old Android tools. Samsung ODE/FMP and KeyMaster were required.

Second, TWRP’s decryption failure was not only an fstab problem. Correcting `/data` block device, encryption footer length, and flags did not make TWRP decrypt. The missing component was Samsung’s stock ODE/KeyMaster userspace path.

Third, stock Samsung `vold` could be run from TWRP recovery, but only after recreating several Android boot-time assumptions: Samsung vendor libraries, `/vendor`, secure-storage daemon, init sockets, vold arguments, fstab aliases, and environment variables.

Fourth, stock `vold` contained a runtime-state guard that prevented password verification when launched outside Android’s normal early-boot crypto path. A targeted two-byte patch skipped this guard and allowed real footer and KeyMaster handling to proceed.

Fifth, after the patch, wrong credentials failed in the expected Samsung ODE/KeyMaster path. This demonstrated that the recovery-side technical problem was solved. Remaining failures were genuine credential failures.

Final conclusion:

```text
The successful technical method was not a decryption bypass. It was a recovery-side reconstruction of Samsung’s stock ODE/KeyMaster decryption path, plus a small patch to remove an early-boot state guard that prevented this path from running inside TWRP.
```

---

## 12. Reproducibility Notes

A reproducible setup requires the following artifacts:

```text
stock /system/bin/vold
patched vold_patched
run_vold_patched_with_sockets
device_try_passwords.sh
start_local_decrypt.sh
run_all.sh
candidate file
```

The phone-side working directory used was:

```text
/cache/decrypt_work
```

Typical phone-side launch:

```sh
/cache/decrypt_work/run_all.sh
```

Success condition:

```text
/dev/block/dm-* appears
/data/media/0 becomes visible after mounting dm-0 read-only
FOUND_PASSWORD.txt is written
```

Failure condition:

```text
CryptfsODE: Failed to decrypt master key
Cryptfs: Password did not match
```

Verification that the method reaches Samsung ODE/KeyMaster:

```sh
adb shell 'logcat -d | grep -iE "CryptfsODE|KeyMaster|obtainKey|AES_256_GCM|Password did not match" | tail -80'
```

---

## 13. Safety and Data Integrity Notes

The following operations were intentionally avoided:

```text
cryptfs enablecrypto
cryptfs erase_footer
format /data
wipe /data
repair encrypted userdata as ext4 before decryption
mount decrypted data read-write before recovery
```

The intended safe mount after success is read-only:

```sh
mount -t ext4 -o ro /dev/block/dm-0 /data
```

Recovered files should then be pulled immediately:

```sh
adb pull /data/media/0 ./phone_recovered/
```

---

## 14. Summary

This research demonstrated that a Samsung Galaxy J7 Prime using Samsung Android 7 ODE/FMP encryption can be made to execute the real Samsung ODE/KeyMaster credential verification path from TWRP recovery. The approach required stock Samsung userspace components, recreated Android init socket behavior, fstab reconstruction, secure-storage support, and a small patch to stock `vold`.

The investigation also clarified why simpler approaches failed: the encryption format was not legacy Android FDE, TWRP fstab patching was insufficient, and stock `vold` was designed to run only after Android’s early boot encryption state had been initialized.

The final result was a working recovery-side credential verification framework. The remaining requirement for actual data recovery is the correct original disk decryption credential.
