#!/usr/bin/env bash
# PenguRP override applier — run once after installing all 3rd-party resources.
# Usage: bash setup.sh /path/to/your/txData/YourBase.base/resources
#
# This copies every file from overrides/ into the matching path in your resources folder,
# exactly replacing the 3rd-party file with the PenguRP-patched version.

set -euo pipefail
RESOURCES="${1:?Usage: bash setup.sh /path/to/resources}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERRIDES="$SCRIPT_DIR/overrides"

if [ ! -d "$RESOURCES" ]; then echo "ERROR: $RESOURCES does not exist"; exit 1; fi

echo "Applying PenguRP overrides to: $RESOURCES"
find "$OVERRIDES" -type f | while read -r src; do
    rel="${src#"$OVERRIDES/"}"
    dst="$RESOURCES/$rel"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  applied: $rel"
done
echo "Done. Run: restart ox_inventory ox_target qbx_core qbx_medical qbx_ambulancejob ps-mdt xt-prison ps-dispatch"
