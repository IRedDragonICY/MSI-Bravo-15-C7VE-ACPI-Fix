# MSI Bravo 15 C7VE ACPI Fixes for Linux

This repository provides ACPI patches (specifically for the DSDT) designed to resolve several BIOS bugs inherent to the MSI Bravo 15 C7VE. These bugs commonly cause `AE_NOT_FOUND`, `AE_ALREADY_EXISTS`, namespace collision errors, and firmware bugs in the Linux kernel log (`dmesg`), which can interfere with power management, thermal sensors, and hardware function keys.

A shell script (`patch.sh`) is provided to safely apply these fixes directly to a raw, decompiled DSDT file.

> **⚠️ WARNING REGARDING ECDT:** 
> Do **NOT** attempt to patch the ECDT (Embedded Controller Data Table) to fix the `Ignoring ECDT due to empty ID string` firmware bug. Forcing early EC initialization by injecting a valid Namepath into the ECDT causes the Linux `msi-wmi` driver to fail, permanently breaking the Fn + Brightness hardware keys. It is safer to let Linux ignore the ECDT and initialize the EC later via the DSDT.

## Applied Fixes (`patch.sh`)

1. **NVIDIA `AE_NOT_FOUND E706` Resolution (Namespace Collision)**
   * **Cause:** The manufacturer improperly named an `OperationRegion` identically to its parent `Device (EC)`. This collision aborts the parsing of the Embedded Controller block, causing dependent devices (like the NVIDIA GPU SSDT looking for `E706`) to fail.
   * **Fix:** Renames the `OperationRegion` to `ECRM`. The core `Device (EC)` is left intact, ensuring the NVIDIA SSDT and MSI WMI drivers (for Fn brightness keys) function correctly.

2. **Duplicate `Device (RTL8)` (`AE_ALREADY_EXISTS`)**
   * **Cause:** An empty, duplicate `Device (RTL8)` declaration causes a boot warning.
   * **Fix:** Comments out the duplicate block.

3. **`SystemCMOS` Region Error (`AE_NOT_EXIST`)**
   * **Cause:** The `VRTC` region is declared outside an appropriate device scope, causing `_Q9A` to fail when reading CMOS data.
   * **Fix:** Relocates the `VRTC` OperationRegion into the `Device (RTC0)` scope and updates the absolute paths for `YEAR`, `MON`, and `DAY` variables.

4. **MSI PTEC Typo Bug**
   * **Cause:** A typo in the manufacturer's logic incorrectly targets `P004` instead of `P00A` when calculating package sizes.
   * **Fix:** Corrects the variable reference to `\_PR.P00A.PPCV`.

5. **`Scope (EC0_)` Error (`AE_NOT_FOUND`)**
   * **Cause:** Supplemental AMD SSDTs are hardcoded to reference a device named `EC0`, while the main DSDT defines it as `EC`. Renaming `EC` to `EC0` globally breaks brightness keys and NVIDIA power management.
   * **Fix:** Injects a "dummy" `Device (EC0)` containing a `_HID` (Hardware ID) and `_STA` set to `Zero` (disabled) just before `Device (PS2K)`. This safely satisfies the AMD SSDTs' scope checks without breaking `msi-wmi`.

6. **`_DSM` Return Type Warning**
   * **Cause:** Certain `_DSM` (Device-Specific Method) functions return an empty `Buffer` instead of the expected `Package`, triggering a strict ACPI type mismatch warning.
   * **Fix:** Replaces the empty `Buffer` returns with empty `Package` returns.

## System Optimizations

In addition to bug fixes, `patch.sh` applies the following performance and power-management optimizations:

1. **Unlock S3 Deep Sleep**
   * Resolves extreme battery drain during suspend and fixes touchpad unresponsiveness upon waking by forcing the BIOS to recognize S3 sleep states.
2. **Remove Linux Power Management Penalty**
   * Bypasses the BIOS OS check that degrades power management features on non-Windows systems, forcing the BIOS to grant full power management capabilities to Linux.
3. **HPET IRQ Storm Fix**
   * Disables legacy HPET IRQs, drastically reducing unnecessary CPU wakes, leading to cooler idle temperatures and improved battery life.
4. **Fix MYEC Bug (Battery, Thermal, Lid Fix)**
   * Corrects SpaceID mapping in `_REG` so battery, CPU temp, and lid sensors are properly exposed to Linux.
5. **Native ACPI Wakeup (Lid & PCIe)**
   * Restores `RHRW` to `_PRW` per ACPI standards, enabling the laptop to wake from sleep when the lid is opened.
6. **Prevent OSVR Downgrade by EC**
   * Prevents `_REG` from downgrading `OSVR`, ensuring Linux retains maximum ACPI support equivalent to Windows 2015/2020.
7. **S3 Instant Wake & DAS3 Sabotage Fix**
   * Removes BIOS blockades against S3 and prevents LAN/PCIe from instantly waking the laptop immediately after suspend.

---
**Critical Note on Versioning (OEM Revision):** 
For the Linux kernel to accept an ACPI override via `initrd`, the patched table's `OEM Revision` must be strictly greater than the one residing in the system firmware. The `patch.sh` script automatically bumps the revision dynamically using the current Unix epoch timestamp to ensure the kernel always applies the changes.

## Usage Instructions

If you wish to patch your own tables manually, follow these steps:

### 1. Dump & Decompile
```bash
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat
iasl -d dsdt.dat
```
*(This generates `dsdt.dsl`)*

### 2. Apply Patches
```bash
chmod +x patch.sh
sudo ./patch.sh dsdt.dsl
```
*(The script will automatically compile and install the override to `/etc/initcpio/acpi_override/dsdt.aml` and rebuild `initramfs`)*

### 3. Verify
Reboot and check `dmesg` to verify the errors are resolved:
```bash
dmesg | grep -i acpi
```