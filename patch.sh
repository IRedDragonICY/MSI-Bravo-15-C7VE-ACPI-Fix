#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with sudo!"
  echo "Example: sudo ./patch.sh"
  exit 1
fi

if ! command -v iasl &> /dev/null; then
    echo "Error: 'iasl' not found. Please install acpica-tools."
    exit 1
fi

# Fallback to original/dsdt.dsl if no parameter is provided
if [ -n "$1" ]; then
    SOURCE_FILE="$1"
else
    if [ -f "original/dsdt.dsl" ]; then
        SOURCE_FILE="original/dsdt.dsl"
        echo "No file provided. Using default: $SOURCE_FILE"
    else
        SOURCE_FILE="dsdt.dsl"
    fi
fi

if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: File $SOURCE_FILE not found."
    echo "Usage: sudo ./patch.sh [path/to/dsdt.dsl]"
    exit 1
fi

# Create a working copy so we don't overwrite the user's original file
FILE="dsdt_patched.dsl"
cp "$SOURCE_FILE" "$FILE"
if [ -n "$SUDO_USER" ]; then
    chown $SUDO_USER:$SUDO_USER "$FILE"
fi

echo "Applying MSI ACPI Fixes to $FILE..."

# ------------------------------------------------------------------
# FIX 1: NVIDIA / Thermal Error Resolution (AE_NOT_FOUND E706)
# Rename the OperationRegion from "EC" to "ECRM" to prevent
# namespace collisions with Device (EC).
# Device (EC) remains intact to ensure NVIDIA SSDT and Fn keys function.
# ------------------------------------------------------------------
sed -i 's/OperationRegion (EC, SystemMemory, 0xFE0B0400/OperationRegion (ECRM, SystemMemory, 0xFE0B0400/' "$FILE"
sed -i 's/Field (EC, ByteAcc, NoLock, Preserve)/Field (ECRM, ByteAcc, NoLock, Preserve)/' "$FILE"

# ------------------------------------------------------------------
# FIX 2: AE_ALREADY_EXISTS Resolution for Device (RTL8)
# Comment out the empty, duplicate RTL8 device declaration.
# ------------------------------------------------------------------
sed -i '/Device (RTL8)/,+3 s/^/\/\//' "$FILE"

# ------------------------------------------------------------------
# FIX 3: SystemCMOS / AE_NOT_EXIST Resolution
# Relocate the VRTC OperationRegion into the Device (RTC0) scope.
# ------------------------------------------------------------------
sed -i '/OperationRegion (VRTC, SystemCMOS, Zero, 0x10)/,+17d' "$FILE"
sed -i '/Name (_HID, EisaId ("PNP0B00") \/\* AT Real-Time Clock \*\/)/a \
                    OperationRegion (VRTC, SystemCMOS, Zero, 0x10)\
                    Field (VRTC, ByteAcc, Lock, Preserve)\
                    {\
                        SEC,    8,\
                        SECA,   8,\
                        MIN,    8,\
                        MINA,   8,\
                        HOR,    8,\
                        HORA,   8,\
                        DAYW,   8,\
                        DAY,    8,\
                        MON,    8,\
                        YEAR,   8,\
                        STAA,   8,\
                        STAB,   8,\
                        STAC,   8,\
                        STAD,   8\
                    }' "$FILE"
sed -i 's/FromBCD (YEAR/FromBCD (\\_SB.PCI0.SBRG.RTC0.YEAR/' "$FILE"
sed -i 's/FromBCD (MON/FromBCD (\\_SB.PCI0.SBRG.RTC0.MON/' "$FILE"
sed -i 's/FromBCD (DAY,/FromBCD (\\_SB.PCI0.SBRG.RTC0.DAY,/' "$FILE"

# ------------------------------------------------------------------
# FIX 4: MSI PTEC Bug Resolution
# Fix incorrect offset overwriting P004 instead of P00A.
# ------------------------------------------------------------------
sed -i 's/\\_PR\.P004\.PPCV = (SizeOf (\\_PR\.P00A\._PSS) - One)/\\_PR.P00A.PPCV = (SizeOf (\\_PR.P00A._PSS) - One)/g' "$FILE"

# ------------------------------------------------------------------
# FIX 5: EC0 Scope Error Resolution (AE_NOT_FOUND)
# Define a dummy Device (EC0) with _STA returning Zero (disabled).
# This satisfies AMD SSDTs utilizing Scope (\_SB.PCI0.SBRG.EC0) 
# without interfering with the primary Device (EC).
# ------------------------------------------------------------------
sed -i '/Device (PS2K)/i \
        Device (EC0)\
        {\
            Name (_HID, EisaId ("PNP0C09"))\
            Name (_STA, Zero)\
        }' "$FILE"

# ------------------------------------------------------------------
# FIX 6: _DSM Warning Resolution
# Return a Package instead of a Buffer to satisfy strict ACPI parsing.
# ------------------------------------------------------------------
sed -i 's/Return (Buffer (Zero) {})/Return (Package (Zero) {})/g' "$FILE"

# ------------------------------------------------------------------
# NEW OPTIMIZATION 4: Fix MYEC Bug (Battery, Thermal, Lid Fix)
# ------------------------------------------------------------------
echo "-> Optimizing: Fixing MYEC Region Bug for Thermal & Battery..."
sed -i '/Method (_REG, 2, NotSerialized)/,/CTSD = Zero/ s/If ((Arg0 == 0x03))/If ((Arg0 == 0x00))/' "$FILE"

# ------------------------------------------------------------------
# NEW OPTIMIZATION 5: Native ACPI Wakeup (Lid & PCIe)
# ------------------------------------------------------------------
echo "-> Optimizing: Restoring Native _PRW Wakeups..."
sed -i 's/Method (RHRW, 0, NotSerialized)/Method (_PRW, 0, NotSerialized)/g' "$FILE"

# ------------------------------------------------------------------
# NEW OPTIMIZATION 6: Prevent OSVR Downgrade by EC
# ------------------------------------------------------------------
echo "-> Optimizing: Blocking EC from downgrading OSVR..."
sed -i '/If (_OSI ("Windows 2015"))/,/OSVR = 0x04/ s/OSVR = 0x05/OSVR = 0x10/g' "$FILE"
sed -i '/If (_OSI ("Windows 2015"))/,/OSVR = 0x04/ s/OSVR = 0x04/OSVR = 0x10/g' "$FILE"

# ------------------------------------------------------------------
# NEW OPTIMIZATION 7: S3 Instant Wake & DAS3 Sabotage Fix
# ------------------------------------------------------------------
echo "-> Optimizing: Patching GPRW for S3 Instant Wake & DAS3..."
sed -i '/If ((DAS3 == Zero))/,+6 s/^/\/\//' "$FILE"
sed -i '/Return (PRWP)/i \
        If ((Arg0 == 0x08) || (Arg0 == 0x0D) || (Arg0 == 0x0E)) {\n            PRWP [One] = Zero\n        }' "$FILE"

# ------------------------------------------------------------------
# AUTOMATIC OEM REVISION BUMP (Epoch Time)
# ------------------------------------------------------------------
OLD_REV=$(grep -o '0x[0-9A-Fa-f]*)$' "$FILE" | head -1 | tr -d ')')
NEW_REV=$(printf "0x%08X" $(date +%s))
sed -i "s/${OLD_REV}/${NEW_REV}/g" "$FILE"

echo "=================================================="
echo "DSDT patching complete. Compiling with iasl..."
echo "=================================================="

FILENAME="${FILE%.*}"
iasl -ve -p "$FILENAME" "$FILE"

if [ ! -f "${FILENAME}.aml" ]; then
    echo "Error: Compilation failed!"
    exit 1
fi

echo "=================================================="
echo "Installing to /etc/initcpio/acpi_override/..."
echo "=================================================="

mkdir -p /etc/initcpio/acpi_override
cp "${FILENAME}.aml" /etc/initcpio/acpi_override/dsdt.aml

echo "Rebuilding initramfs..."
mkinitcpio -P

echo "=================================================="
echo "SUCCESS! The patched DSDT has been installed."
echo "Please reboot your system to apply the changes."
echo "=================================================="