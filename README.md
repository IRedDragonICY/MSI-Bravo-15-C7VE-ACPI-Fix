# MSI Bravo 15 C7VE ACPI Fixes for Linux

This repository provides ACPI patches (specifically for the DSDT and ECDT) designed to resolve several BIOS bugs inherent to the MSI Bravo 15 C7VE. These bugs commonly cause `AE_NOT_FOUND`, `AE_ALREADY_EXISTS`, namespace collision errors, and firmware bugs in the Linux kernel log (`dmesg`), which can interfere with power management, thermal sensors, and hardware function keys.

Shell scripts (`patch.sh` and `patch_ecdt.sh`) are provided to safely apply these fixes directly to raw, decompiled ACPI files.

## Applied Fixes

### DSDT Patches (`patch.sh`)

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
   * **Cause:** Supplemental AMD SSDTs are hardcoded to reference a device named `EC0`, while the main DSDT defines it as `EC`. Renaming `EC` to `EC0` globally breaks brightness keys and NVIDIA power management. Using an `Alias (EC, EC0)` breaks strict ACPI parsing because a `Scope` operator cannot target an Alias.
   * **Fix:** Injects a "dummy" `Device (EC0)` containing a `_HID` (Hardware ID) and `_STA` set to `Zero` (disabled) just before `Device (PS2K)`. This safely satisfies the AMD SSDTs' scope checks without interfering with the actual `Device (EC)`.

6. **`_DSM` Return Type Warning**
   * **Cause:** Certain `_DSM` (Device-Specific Method) functions return an empty `Buffer` instead of the expected `Package`, triggering a strict ACPI type mismatch warning.
   * **Fix:** Replaces the empty `Buffer` returns with empty `Package` returns.

### ECDT Patches (`patch_ecdt.sh`)

1. **`Ignoring ECDT due to empty ID string`**
   * **Cause:** The ECDT (Embedded Controller Data Table) shipped with a completely blank `Namepath`.
   * **Fix:** Injects the correct EC path (`\_SB.PCI0.SBRG.EC`).

---
**Critical Note on Versioning (OEM Revision):** 
For the Linux kernel to accept an ACPI override via `initrd`, the patched table's `OEM Revision` must be strictly greater than the one residing in the system firmware. Both `patch.sh` and `patch_ecdt.sh` automatically bump these revisions (e.g., from `01072009` to `01072010` or higher) to ensure the kernel applies the changes.

## Usage Instructions

If you wish to patch your own tables manually, follow these steps:

### 1. Dump & Decompile
```bash
# Dump DSDT and ECDT
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat
sudo cat /sys/firmware/acpi/tables/ECDT > ecdt.dat

# Decompile to readable DSL
iasl -d dsdt.dat
iasl -d ecdt.dat
```

### 2. Apply Patches
```bash
# Make scripts executable
chmod +x patch.sh patch_ecdt.sh

# Run patches
./patch.sh dsdt.dsl
./patch_ecdt.sh ecdt.dsl
```

### 3. Recompile
```bash
iasl -ve dsdt.dsl
iasl -tc ecdt.dsl
```

### 4. Install via ACPI Override (Arch Linux / mkinitcpio)
```bash
sudo mkdir -p /etc/initcpio/acpi_override
sudo cp dsdt.aml /etc/initcpio/acpi_override/
sudo cp ecdt.aml /etc/initcpio/acpi_override/

# Ensure 'acpi_override' is at the end of your HOOKS array in /etc/mkinitcpio.conf
sudo mkinitcpio -P
```

### 5. Verify
Reboot and check `dmesg` to verify the errors are resolved:
```bash
dmesg | grep -i acpi
```