#!/bin/bash

# Target file - ensure this matches the decompiled original ECDT file
FILE="${1:-ecdt.dsl}"

if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE not found."
    echo "Usage: ./patch_ecdt.sh <ecdt.dsl>"
    exit 1
fi

echo "Applying MSI ACPI ECDT Fix to $FILE..."

# ------------------------------------------------------------------
# FIX 1: ECDT Empty Namepath Resolution
# The manufacturer shipped the ECDT with an empty Namepath ("").
# This injects the correct path: \_SB.PCI0.SBRG.EC
# Note: We must use a single backslash in the generated DSL.
# ------------------------------------------------------------------
sed -i 's/Namepath : ""/Namepath : "\\_SB.PCI0.SBRG.EC"/g' "$FILE"

# ------------------------------------------------------------------
# FIX 2: OEM Revision Bump
# This ensures the Linux kernel recognizes the patched table as
# a newer version and correctly applies the ACPI override.
# Bumps the standard 01072009 to 01072010.
# ------------------------------------------------------------------
sed -i 's/01072009/01072010/g' "$FILE"

echo "ECDT patching complete. Ready for compilation (iasl -tc $FILE)."