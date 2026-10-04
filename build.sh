#!/usr/bin/env bash
# ============================================================
# build.sh - Build & deploy FS25_TaxMod
# Usage:
#   bash build.sh            builds FS25_TaxMod.zip in the repo root only
#   bash build.sh --deploy   builds it AND copies that same file to the mods folder
# ============================================================

set -e

MOD_NAME="FS25_TaxMod"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The zip is written inside the repo root (git-ignored by *.zip), named after
# MOD_NAME on both build paths, as the fleet's other build scripts do.
ZIP_PATH="$SCRIPT_DIR/${MOD_NAME}.zip"

# Windows path for mods folder (adjust if needed)
MODS_DIR="$USERPROFILE/Documents/My Games/FarmingSimulator2025/mods"

echo "============================================"
echo "  Building $MOD_NAME"
echo "============================================"

# Remove old zip
if [ -f "$ZIP_PATH" ]; then
    rm "$ZIP_PATH"
    echo "  Removed old zip"
fi

# Build new zip — must use forward slashes inside (FS25 requirement)
# PowerShell Compress-Archive creates backslash paths — use 'zip' or this python fallback
cd "$SCRIPT_DIR"

if command -v zip &>/dev/null; then
    # Paths inside zip are relative to CWD (already cd'd to SCRIPT_DIR).
    # Exclude patterns must use the same relative form.
    zip -r "$ZIP_PATH" . \
        --exclude "./*.sh" \
        --exclude "./.claude/*" \
        --exclude "./.git/*" \
        --exclude "./.git" \
        --exclude "./.github/*" \
        --exclude "./*.md" \
        --exclude "./.gitignore" \
        --exclude "./__MACOSX/*" \
        --exclude "./*.DS_Store" \
        --exclude "./*.zip" \
        --exclude "./tools/*"
    echo "  Built via zip"
else
    # Python fallback — try python3, then python, then the Windows launcher (py).
    # Each candidate has to RUN, not merely exist: on Windows `python3` resolves to the Microsoft
    # Store alias stub, which `command -v` finds happily and which then prints "Python was not
    # found" and exits 49, so a presence test alone picks an interpreter that cannot build.
    PYTHON_CMD=""
    for _py in python3 python py; do
        if command -v "$_py" &>/dev/null && "$_py" -c "import sys" &>/dev/null; then
            PYTHON_CMD="$_py"
            break
        fi
    done
    if [ -z "$PYTHON_CMD" ]; then
        echo "ERROR: no working Python found (tried python3, python, py)"; exit 1
    fi
    # MOD_NAME is passed in, so the zip is named after the mod, not after the
    # folder (a worktree folder has another name), and lands where ZIP_PATH says.
    $PYTHON_CMD - "$MOD_NAME" <<'PYEOF'
import zipfile, os, sys

MOD_DIR = os.getcwd()
ZIP_PATH = os.path.join(MOD_DIR, sys.argv[1] + ".zip")

EXCLUDE_DIRS  = {".git", ".claude", ".github", "__MACOSX", "tools"}
EXCLUDE_EXTS  = {".sh", ".md", ".DS_Store", ".zip"}
EXCLUDE_FILES = {".gitignore", ".git"}  # in a worktree .git is a FILE, not a directory

with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(MOD_DIR):
        # Prune excluded dirs in-place
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            if fname in EXCLUDE_FILES:
                continue
            if any(fname.endswith(ext) for ext in EXCLUDE_EXTS):
                continue
            full_path = os.path.join(root, fname)
            # Paths relative to MOD_DIR → files land at ZIP root (not in a subfolder)
            arc_name = os.path.relpath(full_path, MOD_DIR)
            # Enforce forward slashes (FS25 requirement)
            arc_name = arc_name.replace("\\", "/")
            zf.write(full_path, arc_name)
            print(f"  + {arc_name}")

print(f"\n  ZIP created: {ZIP_PATH}")
PYEOF
fi

# Both paths must have written exactly ZIP_PATH (the old zip was removed above),
# so --deploy can only ever copy the file this run built.
if [ ! -f "$ZIP_PATH" ]; then
    echo "ERROR: the build did not write $ZIP_PATH"
    exit 1
fi

echo ""
echo "  Output: $ZIP_PATH"

# --deploy flag: copy zip to mods folder
if [[ "$1" == "--deploy" ]]; then
    echo ""
    echo "  Deploying to mods folder..."

    if [ ! -d "$MODS_DIR" ]; then
        echo "  WARNING: Mods folder not found at: $MODS_DIR"
        echo "  Edit MODS_DIR in build.sh if your path differs."
        exit 1
    fi

    # Remove old deployed version
    if [ -f "$MODS_DIR/${MOD_NAME}.zip" ]; then
        rm "$MODS_DIR/${MOD_NAME}.zip"
    fi

    cp "$ZIP_PATH" "$MODS_DIR/${MOD_NAME}.zip"
    echo "  Deployed: $MODS_DIR/${MOD_NAME}.zip"
fi

echo ""
echo "  Done. Check log.txt for [TaxMod] entries after launching."
echo "============================================"
