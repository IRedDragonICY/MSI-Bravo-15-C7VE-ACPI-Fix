#!/bin/bash

# Target file - ensure this matches the decompiled original DSDT file
FILE="${1:-dsdt.dsl}"

if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE not found."
    echo "Usage: ./patch.sh <dsdt.dsl>"
    exit 1
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
# Remove original VRTC block
sed -i '/OperationRegion (VRTC, SystemCMOS, Zero, 0x10)/,+17d' "$FILE"

# Insert VRTC block into Device (RTC0)
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

# Update absolute paths for _Q9A method
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

echo "DSDT patching complete. Ready for compilation (iasl -ve $FILE)."