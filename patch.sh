#!/bin/bash

# Target file - ensure this matches the decompiled original DSDT file
FILE="${1:-dsdt.dsl}"

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script with sudo!"
  echo "Example: sudo ./patch.sh dsdt.dsl"
  exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE not found."
    echo "Usage: sudo ./patch.sh <dsdt.dsl>"
    exit 1
fi

if ! command -v iasl &> /dev/null; then
    echo "Error: 'iasl' not found. Please install acpica-tools."
    exit 1
fi

echo "Applying MSI ACPI Fixes to $FILE..."

# ------------------------------------------------------------------
# FIX 1: NVIDIA / Thermal Error Resolution (AE_NOT_FOUND E706)
# ------------------------------------------------------------------
sed -i 's/OperationRegion (EC, SystemMemory, 0xFE0B0400/OperationRegion (ECRM, SystemMemory, 0xFE0B0400/' "$FILE"
sed -i 's/Field (EC, ByteAcc, NoLock, Preserve)/Field (ECRM, ByteAcc, NoLock, Preserve)/' "$FILE"

# ------------------------------------------------------------------
# FIX 2: AE_ALREADY_EXISTS Resolution for Device (RTL8)
# ------------------------------------------------------------------
sed -i '/Device (RTL8)/,+3 s/^/\/\//' "$FILE"

# ------------------------------------------------------------------
# FIX 3: SystemCMOS / AE_NOT_EXIST Resolution
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
# ------------------------------------------------------------------
sed -i 's/\\_PR\.P004\.PPCV = (SizeOf (\\_PR\.P00A\._PSS) - One)/\\_PR.P00A.PPCV = (SizeOf (\\_PR.P00A._PSS) - One)/g' "$FILE"

# ------------------------------------------------------------------
# FIX 5: EC0 Scope Error Resolution (AE_NOT_FOUND)
# ------------------------------------------------------------------
# KITA MENGGUNAKAN _ADR BUKAN _HID AGAR LINUX TIDAK BINGUNG KARENA ADA 2 EC.
sed -i '/Device (PS2K)/i \
        Device (EC0)\
        {\
            Name (_ADR, Zero)\
            Name (_STA, Zero)\
        }' "$FILE"

# ------------------------------------------------------------------
# FIX 6: _DSM Warning Resolution
# ------------------------------------------------------------------
sed -i 's/Return (Buffer (Zero) {})/Return (Package (Zero) {})/g' "$FILE"

# ------------------------------------------------------------------
# FIX 7: RELATIVE PATH BUG (PENYEBAB UTAMA BRIGHTNESS MATI!)
# ------------------------------------------------------------------
sed -i 's/\^\^\^GPP0/\\_SB.PCI0.GPP0/g' "$FILE"
sed -i 's/\^\^\^GP17/\\_SB.PCI0.GP17/g' "$FILE"
sed -i 's/\^\^\^\^NPCF/\\_SB.NPCF/g' "$FILE"


# ------------------------------------------------------------------
# OPTIMIZATION 1: Fix MYEC Bug (Battery, Thermal, Lid Fix)
# Corrects SpaceID mapping so battery, CPU temp, and lid sensors work.
# ------------------------------------------------------------------
echo "-> Optimizing: Fixing MYEC Region Bug for Thermal & Battery..."
sed -i '/Method (_REG, 2, NotSerialized)/,/CTSD = Zero/ s/If ((Arg0 == 0x03))/If ((Arg0 == 0x00))/' "$FILE"

# ------------------------------------------------------------------
# OPTIMIZATION 2: Lid Wake ONLY (Avoids AE_ALREADY_EXISTS on PCIe)
# ------------------------------------------------------------------
echo "-> Optimizing: Restoring Native _PRW Wakeups for LID0 only..."
sed -i '/Device (LID0)/,/}/ s/Method (RHRW, 0, NotSerialized)/Method (_PRW, 0, NotSerialized)/g' "$FILE"

# ------------------------------------------------------------------
# OPTIMIZATION 3: Prevent EC from downgrading OS capabilities
# Note: Using 0x0F instead of 0x10 to prevent 4-bit overflow!
# ------------------------------------------------------------------
echo "-> Optimizing: Blocking EC from downgrading OSVR..."
sed -i '/Method (_REG, 2, NotSerialized)/,/CTSD = Zero/ {
    s/OSVR = 0x05/OSVR = 0x0F/g
    s/OSVR = 0x04/OSVR = 0x0F/g
    s/OSVR = 0x03/OSVR = 0x0F/g
    s/OSVR = 0x02/OSVR = 0x0F/g
    s/OSVR = One/OSVR = 0x0F/g
}' "$FILE"

# ------------------------------------------------------------------
# OPTIMIZATION 4: S3 Instant Wake Fix (Blocks PCIe root/USB Wake)
# ------------------------------------------------------------------
echo "-> Optimizing: Patching GPRW for S3 Instant Wake & DAS3..."
sed -i '/If ((DAS3 == Zero))/,+6 s/^/\/\//' "$FILE"
sed -i '/Return (PRWP)/i \
        If ((Arg0 == 0x08) || (Arg0 == 0x0D) || (Arg0 == 0x0E) || (Arg0 == 0x0F)) {\n            PRWP [One] = Zero\n        }' "$FILE"

# ------------------------------------------------------------------
# OPTIMIZATION 5: Unlock Deep S3 Sleep & Remove Linux Penalty
# Note: Using 0x0F instead of 0x10 to prevent 4-bit overflow!
# ------------------------------------------------------------------
echo "-> Optimizing: Unlocking S3 Deep Sleep..."
sed -i 's/Name (XS3, Package/Name (_S3, Package/' "$FILE"
sed -i '/If (MCTH (_OS, "Linux"))/,/}/ s/OSVR = 0x03/OSVR = 0x0F/' "$FILE"


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