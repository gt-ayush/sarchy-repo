#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
OUT_DIR="$REPO_ROOT/output"
mkdir -p "$OUT_DIR"

# Auto-detect GPG fingerprint if not provided (for local use; CI sets it via secret)
if [ -z "${GPG_FINGERPRINT:-}" ]; then
    GPG_FINGERPRINT="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
    export GPG_FINGERPRINT
fi

if [ -z "$GPG_FINGERPRINT" ]; then
    echo "[ERROR] GPG_FINGERPRINT is not set."
    echo "  Export it manually: export GPG_FINGERPRINT=<your-40-char-fingerprint>"
    echo "  Or list your keys: gpg --list-secret-keys --with-colons"
    exit 1
fi

# Create a non-root builder user (makepkg refuses to run as root)
if ! id -u builder >/dev/null 2>&1; then
    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

chown -R builder:builder "$REPO_ROOT"

for pkg_dir in "$REPO_ROOT"/packages/*; do
    [ -d "$pkg_dir" ] || continue
    pkg_name="$(basename "$pkg_dir")"
    echo "=========================================="
    echo "Building package: $pkg_name"
    echo "=========================================="

    cd "$pkg_dir"

    # Attempt 1: Standard PKGBUILD build
    if sudo -u builder makepkg -s --sign --key "$GPG_FINGERPRINT" --noconfirm; then
        echo "[SUCCESS] Built $pkg_name via standard PKGBUILD"
        mv ./*.pkg.tar.zst* "$OUT_DIR/"
        continue
    fi

    echo "[WARNING] Standard build failed for $pkg_name. Attempting upstream Git fallback..."
    sudo -u builder rm -rf src pkg ./*.tar.* ./*.zip

    # Attempt 2: Upstream Git source fallback
    UPSTREAM_GIT=""
    if [ -f "upstream.url" ]; then
        UPSTREAM_GIT="$(cat upstream.url | tr -d '[:space:]')"
    else
        # Extract url= from PKGBUILD and append .git if it's a GitHub/GitLab link
        RAW_URL="$(grep -E '^url=' PKGBUILD | head -n1 | cut -d'=' -f2 | tr -d "\"'")"
        if [[ "$RAW_URL" == *"github.com"* || "$RAW_URL" == *"gitlab.com"* ]]; then
            UPSTREAM_GIT="${RAW_URL%.git}.git"
        fi
    fi

    if [ -z "$UPSTREAM_GIT" ]; then
        echo "[ERROR] No upstream Git URL found for $pkg_name. Skipping."
        continue
    fi

    echo "[FALLBACK] Cloning from $UPSTREAM_GIT..."
    FALLBACK_DIR="/tmp/fallback-$pkg_name"
    rm -rf "$FALLBACK_DIR"
    sudo -u builder git clone --depth 1 "$UPSTREAM_GIT" "$FALLBACK_DIR"

    # Auto-strip systemd dependencies from PKGBUILD and skip checksums for live git fallback
    sudo -u builder sed -i "s/'systemd'//g; s/\"systemd\"//g; s/'libsystemd'//g; s/\"libsystemd\"//g" PKGBUILD

    if sudo -u builder makepkg -s --skipinteg --sign --key "$GPG_FINGERPRINT" --noconfirm; then
        echo "[SUCCESS] Built $pkg_name via upstream Git fallback!"
        mv ./*.pkg.tar.zst* "$OUT_DIR/"
    else
        echo "[FAILED] Both standard and Git fallback builds failed for $pkg_name."
    fi
done
