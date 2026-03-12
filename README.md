# MSI Bravo 15 C7VE (MS-158N) ACPI Fixes for Linux

This repository provides fully patched and compiled ACPI tables (DSDT and ECDT) for the **MSI Bravo 15 C7VE**. These fixes resolve several notorious BIOS/Firmware bugs that cause ACPI errors, power management failures, and namespace collisions on Linux.

## Fixed Bugs

1. **`AE_ALREADY_EXISTS` (OperationRegion Collision)**
   * **Symptom:** Logs flooded with `Failure creating named object [\M040], AE_ALREADY_EXISTS` and missing EC variables.
   * **Cause:** The manufacturer improperly named an `OperationRegion` the exact same name as its parent `Device (EC)`. This collision aborts the parsing of the Embedded Controller block. Because the block aborts, GPU power-management methods (like `PEGP.GPS`) fail to find variables like `E706` and throw `AE_NOT_FOUND`.
   * **Fix:** Renamed the internal `OperationRegion` names to `ECM1` and `ECM2` within the DSDT, allowing the entire EC to initialize properly.

2. **`AE_NOT_FOUND` on `\_SB.PCI0.SBRG.EC0` (Broken SSDT Scopes)**
   * **Symptom:** `Skipping parse of AML opcode: Scope` and `Could not resolve symbol [\_SB.PCI0.SBRG.EC0], AE_NOT_FOUND`.
   * **Cause:** Several supplemental AMD tables (SSDT9, SSDT16, SSDT24) are hardcoded to look for a device named `EC0`, while the main DSDT declares it as `EC`. Overriding these SSDTs directly causes namespace crashes because they share the identical `AmdTable` ID with 20 other tables.
   * **Fix:** Injected a benign "dummy" `Device (EC0)` into the main DSDT without a Hardware ID (`_HID`). This satisfies the SSDTs' scope-checking without confusing the Linux `acpi-ec` driver.

3. **`No handler for Region [VRTC] [SystemCMOS]`**
   * **Symptom:** Errors related to the `_Q9A` method failing to read CMOS data.
   * **Fix:** Commented out the broken `FromBCD` variable reads inside the `_Q9A` method in the DSDT.

4. **`Ignoring ECDT due to empty ID string`**
   * **Symptom:** Kernel logs report an early firmware bug for the ECDT.
   * **Cause:** The ECDT (Embedded Controller Data Table) shipped with a completely blank `Namepath`.
   * **Fix:** Decompiled the ECDT and added the proper path `\_SB.PCI0.SBRG.EC`, allowing early-boot EC initialization.

## Repository Structure

* `patches/` - The decompiled and human-readable `.dsl` source code containing the fixes.
* `compiled/` - The compiled `.aml` binaries ready to be loaded by the Linux kernel.

## How to Install (Arch Linux / mkinitcpio)

This method safely loads the patched tables before the kernel boots.

1. Copy the compiled `.aml` files into the initcpio overrides directory:
   ```bash
   sudo mkdir -p /etc/initcpio/acpi_override
   sudo cp compiled/dsdt.aml /etc/initcpio/acpi_override/
   sudo cp compiled/ecdt.aml /etc/initcpio/acpi_override/
   ```

2. Edit your mkinitcpio configuration to enable the override hook. Open `/etc/mkinitcpio.conf` and add `acpi_override` to the end of the `HOOKS` array. It should look similar to this:
   ```bash
   HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck acpi_override)
   ```

3. Regenerate your initramfs images:
   ```bash
   sudo mkinitcpio -P
   ```

4. Reboot your system. You can verify the tables loaded by checking `dmesg`:
   ```bash
   journalctl -b -k | grep "Table Upgrade"
   ```

## Note on Nvidia `_DSM` Warnings
You may still see warnings similar to:
`ACPI Warning: \_SB.NPCF._DSM: Argument #4 type mismatch - Found [Buffer], ACPI requires [Package]`

**This is normal and safe.** It is a known bug strictly inside the proprietary Nvidia Linux driver where it sends a Buffer instead of a Package. The Linux ACPI interpreter automatically corrects the data type on the fly, so power management works correctly regardless. It cannot be fixed via ACPI tables.
