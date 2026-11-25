# Sarchy Linux Package Repository

Automated, GPG-signed pacman repository for Sarchy Linux (Artix/OpenRC-based).
Built and published via GitHub Actions on every push, every 12 hours (cron), or manually.

## Repository Structure

```
sarchy-repo/
├── .github/
│   └── workflows/
│       └── build-repo.yml        # GitHub Actions pipeline
├── packages/
│   └── sarchy-keyring/
│       ├── PKGBUILD              # Builds the GPG keyring package
│       ├── sarchy.gpg            # Exported public key (ASCII-armored)
│       └── sarchy-trusted        # Ownertrust record (FPR:4:)
├── external.repos                # One standalone Git repo URL per line (e.g. sarchy-branding)
├── scripts/
│   └── smart-build.sh            # Build script with upstream Git fallback
└── README.md
```

## Prerequisites (GitHub Secrets)

Add these in **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `GPG_PRIVATE_KEY` | Base64-encoded private key: `gpg --armor --export-secret-keys <FPR> \| base64 -w 0` |
| `GPG_PASSPHRASE` | Your key passphrase (blank if none) |
| `GPG_FINGERPRINT` | 40-character GPG fingerprint |

## How It Works

1. You push a new/updated `PKGBUILD` to `packages/<tool>/`.
2. GitHub Actions spins up an **Artix Linux container**.
3. It tries `makepkg -s --sign` on every package in `packages/`.
4. If a standard build fails, it falls back to building from upstream Git source (strips `systemd` references, skips checksums).
5. Successful builds are signed with your GPG key and moved to `output/`.
6. `repo-add --sign` generates `sarchy-repo.db.tar.gz`.
7. Everything is published to the GitHub Release named **`repo`**.

The pipeline runs on:
- `push` to `main` touching `packages/**` or `scripts/**`
- `schedule`: every 12 hours (`0 */12 * * *`)
- `workflow_dispatch` (manual)

## Local Testing (Docker / Podman)

To test the build locally without polluting your host, run the script inside an
Artix container — exactly like GitHub Actions:

```bash
export GPG_FINGERPRINT=0B71295264C552D92247710DBA492ABDFDA5BC4E

# Via docker (or podman — auto-detected)
USE_CONTAINER=1 ./scripts/smart-build.sh
```

The script re-executes itself inside `artixlinux/artixlinux:latest` with your
repository mounted at `/sarchy-repo`. All git clones are shallow (`--depth 1`),
so only the latest commit is downloaded — faster and smaller.

Without `USE_CONTAINER=1`, the script runs directly on your host as your current
user (makepkg works fine as non-root locally).

## Shallow Clones

Every `git clone` in `smart-build.sh` uses `--depth 1` — only the latest commit
is fetched, never the full history. This applies to both:
- `packages/*` upstream Git fallback builds
- `external.repos` standalone repo builds

## Adding a New Package

**Option A — Keep PKGBUILD inside this repo:**
1. Create `packages/<tool-name>/`.
2. Add a `PKGBUILD` (remove `systemd` from `depends` for Artix/OpenRC compatibility).
3. (Optional) Add `upstream.url` with a raw Git clone URL for the fallback builder.

**Option B — Build from a standalone repo (e.g. `sarchy-branding`):**
1. Add the standalone Git repo URL to `external.repos` (one URL per line).
2. Develop and maintain the PKGBUILD in its own repo — `sarchy-repo` will clone, compile, sign, and publish it automatically.

4. `git push origin main` — GitHub Actions compiles, signs, updates the repo database, and publishes automatically.

Example `packages/sometool/PKGBUILD`:

```bash
pkgname=sometool
pkgver=1.0
pkgrel=1
pkgdesc="Example security tool"
arch=('x86_64')
url="https://github.com/example/sometool"
license=('MIT')
source=("sometool::git+https://github.com/example/sometool.git")
sha256sums=('SKIP')

build() {
    cd "$srcdir/sometool"
    make
}

package() {
    cd "$srcdir/sometool"
    make DESTDIR="$pkgdir" install
}
```

## Installing the Repository on a Client Machine

```bash
# 1. Install the keyring package from your repo
sudo pacman -S sarchy-keyring

# 2. Import the key into pacman's keyring
sudo pacman-key --populate sarchy

# 3. Trust your signing key
sudo pacman-key --lsign <YOUR_FINGERPRINT>

# 4. Add the repository to /etc/pacman.conf
# [sarchy-repo]
# SigLevel = Required DatabaseOptional
# Server = https://github.com/gt-ayush/sarchy-repo/releases/download/repo

# 5. Sync and install
sudo pacman -Syu
```

> Replace `<YOUR_FINGERPRINT>` with your actual 40-character GPG fingerprint.