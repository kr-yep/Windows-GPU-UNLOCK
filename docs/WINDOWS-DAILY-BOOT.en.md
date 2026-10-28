# Daily boot for a local profile: production build, Secure Boot enforcing, internal ESP

This fork adds four things on top of the [new-machine local profile](NEW-MACHINE.en.md):

1. **Production build** (`-Production`). The same unlock without Esc waits, graph captures or
   success logs. Every per-boot hardware gate stays (exact card and PROM, cold state, driver
   ownership, BME/resources, DMA limits, final handoff check). On a refusal before any driver is
   released it returns to the firmware boot order, so the next entry (Windows) starts normally, just without the unlock.
   The diagnostic build is unchanged.
2. **Secure Boot enforcing without a signing key.** The production child accepts Secure Boot on.
   You append the Authenticode SHA-256 of the two EFI files to db in firmware setup.
3. **Internal ESP for a local profile.** Upstream keeps local profiles on USB with a human choosing
   the boot entry. Here the production package can live on a dedicated ESP and run on every boot.
4. **`Headless.ps1 -Uninstall`**, so a rebuilt package (after a BIOS update or card change) can be
   installed again.

Evidence: one machine, one run per boot type, see
[x870e-aero-3090-local](../evidence/x870e-aero-3090-local/README.md). Treat everything else
(other boards, other firmware vendors, sleep/hibernate) as untested.

## Before you start

- Finish [NEW-MACHINE](NEW-MACHINE.en.md) first: probe, profile, `test-profile.ps1` evidence, and one
  successful **diagnostic** USB unlock. Do not start with the production or ESP build.
- **Clone to a short path such as `C:\gu`.** The child EFI path inside the build tree is about 195
  characters; with a deep clone it passes Windows PowerShell 5.1's 260-character limit and the
  scripts fail with `DirectoryNotFoundException` or `Cannot find path`. `subst W: <repo>` also works,
  but it must be created inside the same administrator window that runs the scripts.
- C: fully decrypted and BitLocker protection off, as upstream requires.
- Any change to source or scripts invalidates the evidence: rerun `research/profile/test-profile.ps1`
  before building, as for the diagnostic build.

## 1. Production USB (optional first step)

```powershell
.\research\headless\build-usb.ps1 -WindowsEspGuid '<Windows ESP GUID>' -HardwareProfile local -Production -Clang <clang.exe> -LldLink <lld-link.exe>
.\research\headless\stage-usb.ps1 -Drive F -Assets <assets folder> -Production
```

Boot it once from the firmware boot menu with Secure Boot off and benchmark. The USB and ESP
production builds share `internal-boot/boot/build/headless-production`, so build and stage one
package at a time.

## 2. Keep Secure Boot enforcing (db Append)

This allows two unsigned images you built, by hash, without disabling Secure Boot for everything
else. It does not add a key, and nothing else is trusted by it. The trade-off: those exact files
will run on this machine, and the firmware must be in a mode that lets you edit db.

1. Back up the current keys (administrator PowerShell; read-only):

   ```powershell
   .\tools\secureboot\Backup-SecureBootKeys.ps1
   ```

2. Build the list from the **unsigned** images you will boot. For the USB package the staged files
   are `F:\EFI\BOOT\BOOTX64.EFI` and `F:\EFI\WindowsGPUUnlock\UNLOCK-HEADLESS.EFI`; for the ESP
   package use the build outputs right after building (wrapper
   `internal-boot\boot\build\headless-production\HEADLESS.EFI`, child path from
   `Get-HeadlessChildPath -Production` in `internal-boot\install\headless-package.ps1`).

   ```powershell
   python -I .\tools\secureboot\make_db_esl.py F:\SB\db-append.esl <wrapper.efi> <child.efi>
   ```

   Put the `.esl` on a FAT32 USB stick the firmware can read.
3. In firmware setup, append that file to db. **Only tested on Gigabyte X870E AERO X3D WOOD, BIOS F4:**
   Secure Boot → Secure Boot Mode **Custom** → Expert Key Management → Authorized Signatures (db) →
   **Append** → "load factory default db?" **No** (load from external media) → choose the `.esl`.
   On this firmware, do **not** use Restore Factory Keys and do not switch Custom back to Standard:
   both restore factory keys and drop the appended list. Enable Secure Boot, save and exit.
4. Back in Windows (administrator), confirm only db changed, by exactly the appended entries:

   ```powershell
   .\tools\secureboot\Compare-SecureBootKeys.ps1 -Backup <backup folder> -Esl F:\SB\db-append.esl
   ```

   It must end with `Result: as expected`. If not, make no further firmware changes.

Every rebuild that changes an EFI file needs a new list and a new Append. Old entries can stay.

## 3. Internal ESP

### Create the dedicated ESP (no verified recipe)

You need a separate GPT partition, type EFI System (`{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}`),
FAT32, at least 1 GiB, not the Windows ESP. The scripts never create partitions. Two warnings
from this fork's only attempt, both on Windows 11 build 26200:

- Retyping a freshly created, mounted FAT32 volume with
  `Set-Partition -DriveLetter U -GptType '{c12a7328-...}'` **on the Windows system disk froze the
  PC** (bugcheck, no dump; cause not proven; the GPU was unlocked at the time). The new partition
  was lost; nothing else was damaged.
- On a second disk the same steps finished, but the new partition received the same partition GUID
  as that disk's recovery partition, and Windows took the whole disk offline
  (`OfflineReason Collision`). Choosing **Online** for that disk in Disk Management gave the new
  partition a fresh GUID and the disk came back with its data intact.

Back up first, and check afterwards that no two partitions share a GUID:

```powershell
Get-Partition | Group-Object Guid | Where-Object Count -gt 1
```

Disk Management and diskpart `assign` cannot give an ESP-typed partition a drive letter. Use
`mountvol` with the volume path **in single quotes** (unquoted, PowerShell parses `{...}` as a
script block and mountvol only prints its help):

```powershell
Get-CimInstance Win32_Volume | Where-Object Label -eq GPUUNLOCK | Select-Object DeviceID,FileSystem,Capacity
mountvol U: '\\?\Volume{<GUID from DeviceID>}\'
```

The scripts find the partition by this letter, so keep it mounted while running them. Firmware
boot does not need it.

### Configure, build, install

Administrator PowerShell at the repository root (reading an ESP needs administrator rights):

```powershell
.\internal-boot\Configure.ps1 -UnlockDriveLetter U -WindowsEspGuid '<Windows ESP GUID>' -HardwareProfile local
.\research\headless\build-unlock.ps1 -HardwareProfile local -Production -Clang <clang.exe> -LldLink <lld-link.exe>
.\internal-boot\Headless.ps1 -Production -Assets <assets folder>             # copy and verify files only
.\internal-boot\Headless.ps1 -Production -Assets <assets folder> -Register   # new entry, last in boot order
```

The Windows ESP GUID is the `IsSystem` partition holding `EFI\Microsoft\Boot\bootmgfw.efi`. If
an older Windows disk is also attached, its ESP has Windows boot files too; use the one you boot.

With Secure Boot on, do step 2 for the ESP wrapper and child, then test once by choosing
**GPU Headless UNLOCK - EXPERIMENTAL** in the firmware boot menu and benchmarking. Only after that:

```powershell
.\internal-boot\Headless.ps1 -Production -EnableAutomatic -ConfirmedSuccess
```

This puts the entry first and Windows second, and turns Fast Startup off, as upstream
requires for automatic boot. Test a Windows restart and a full shutdown/power-on, with a
benchmark after each.

## 4. Turning it off, BIOS updates, a new card

- **Windows first, keep everything:** `.\internal-boot\Headless.ps1 -RestoreWindowsFirst`.
  Restores the previous Fast Startup setting. Use this before replacing the graphics card.
- **Remove it:** `.\internal-boot\Headless.ps1 -Uninstall` (letter still mounted). It puts Windows
  first, restores Fast Startup, deletes only the saved boot entry after matching its device, path
  and name, and removes only the staged EFI and asset files; other files on the ESP stay. It needs
  no build, so it works after a BIOS update. Host-tested only.
- **After a BIOS update:** the package refuses the new BIOS. Regenerate the profile from step 1 of
  NEW-MACHINE, rebuild, then `-Uninstall`, stage, `-Register`, db Append for the new hashes, test,
  `-EnableAutomatic`.
- The ESP partition, the drive letter (`mountvol U: /d`) and the db entries can stay; none of them
  affects Windows or another card.

## 5. Is it still unlocking?

The production build is silent, and a refusal before the GPU is touched simply boots Windows
locked. Check now and then with a benchmark (FP16 around 70 TFLOPS on a 3090 means locked). Then:

- Look for `RTX3090-UNLOCK\FAILURE.TXT` or `CHILD-FAILURE.TXT` on the ESP (administrator).
- Check the boot order: firmware or Windows updates can put Windows Boot Manager first again;
  rerun `-EnableAutomatic -ConfirmedSuccess`.

`wsl: Failed to mount U:\` at WSL start-up is harmless: WSL cannot mount an ESP. Unmount the
letter with `mountvol U: /d` if it bothers you, and mount it again before running the scripts.
