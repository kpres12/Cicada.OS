#!/usr/bin/env bash
# Build the Cicada.OS x86_64 ISO with mkarchiso.
# Intended to run inside the linux/amd64 Arch builder container (or native Arch).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${CICADA_OUT:-${ROOT}/out}"
WORK="${CICADA_WORK:-${ROOT}/work}"
PROFILE="${CICADA_PROFILE_DIR:-${WORK}/profile}"

if ! command -v mkarchiso >/dev/null 2>&1; then
  echo "error: mkarchiso not found. Install archiso on an Arch host." >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "error: ISO target is x86_64 (Intel MBA). This host is $(uname -m)." >&2
  echo "  On Apple Silicon, use: ./scripts/build-iso-docker.sh" >&2
  exit 1
fi

mkdir -p "${OUT}" "${WORK}"
export CICADA_PROFILE_DIR="${PROFILE}"

# SOURCE_DATE_EPOCH drives iso_label/iso_version in profiledef.sh and the
# BUILD-ID stamp in assemble-profile.sh — both fall back to wall-clock "now"
# when it is unset, which means two builds of the identical commit can never
# match bit-for-bit. Default it to the commit's own timestamp: deterministic
# per source tree, and it moves only when the tree actually changes, which is
# the property "reproducible" is supposed to mean. A caller (a reproducibility
# check building the same commit twice) can still pin an explicit value.
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]] && git -C "${ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  export SOURCE_DATE_EPOCH="$(git -C "${ROOT}" log -1 --format=%ct)"
fi

# Package-set pin. SOURCE_DATE_EPOCH fixes every timestamp, but not WHICH
# packages get installed: pacstrap resolves against live rolling mirrors, so
# two builds of the same commit forty minutes apart pull whatever was pushed in
# between, and the images differ for a reason no timestamp pin can touch.
#
# CICADA_PKG_SNAPSHOT=<dir> freezes the repo databases into <dir> on the first
# build that sees it empty, and every later build with the same <dir> resolves
# against those frozen databases instead. The builder's mirrorlist (the one the
# profile's pacman.conf Includes for pacstrap) gets file://<dir> first, so the
# databases come from the snapshot; package files are not in it, so pacman
# falls through to the live mirrors for them — or, with a shared
# /var/cache/pacman/pkg, never downloads them at all. Package signatures live
# in the databases and are still verified. Build-time only: the image's own
# mirrorlist comes from packages, not from the builder. Unset: as before.
if [[ -n "${CICADA_PKG_SNAPSHOT:-}" ]]; then
  [[ "${EUID}" -eq 0 ]] || {
    echo "error: CICADA_PKG_SNAPSHOT rewrites /etc/pacman.d/mirrorlist; run as root (the builder container)" >&2
    exit 1
  }
  snap="${CICADA_PKG_SNAPSHOT}"
  mapfile -t live_mirrors < <(grep -E '^[[:space:]]*Server[[:space:]]*=' /etc/pacman.d/mirrorlist \
                               | grep -v 'file://' | sed -E 's/^[[:space:]]*Server[[:space:]]*=[[:space:]]*//')
  [[ ${#live_mirrors[@]} -gt 0 ]] || { echo "error: no Server lines in /etc/pacman.d/mirrorlist" >&2; exit 1; }
  pinned_from=""
  if [[ -f "${snap}/MIRROR" ]]; then
    pinned_from="$(<"${snap}/MIRROR")"
    echo "==> package databases: reusing snapshot ${snap} (frozen from ${pinned_from})"
  else
    # All databases from ONE mirror, so they describe one consistent sync.
    for m in "${live_mirrors[@]}"; do
      ok=1
      for repo in core extra multilib; do
        url="${m//\$repo/${repo}}"; url="${url//\$arch/x86_64}"
        mkdir -p "${snap}/${repo}/os/x86_64"
        curl -fsSL --retry 2 --max-time 300 -o "${snap}/${repo}/os/x86_64/${repo}.db" "${url}/${repo}.db" \
          || { ok=0; break; }
      done
      if [[ ${ok} -eq 1 ]]; then pinned_from="${m}"; break; fi
    done
    [[ -n "${pinned_from}" ]] || { echo "error: could not fetch repo databases from any mirror" >&2; exit 1; }
    printf '%s\n' "${pinned_from}" > "${snap}/MIRROR"
    echo "==> package databases: froze snapshot ${snap} from ${pinned_from}"
  fi
  # Snapshot first; then the mirror it was frozen from (most likely to still
  # carry those exact versions); then the rest.
  {
    # shellcheck disable=SC2016  # $repo/$arch are pacman's variables, not ours
    printf 'Server = file://%s/$repo/os/$arch\n' "${snap}"
    printf 'Server = %s\n' "${pinned_from}"
    for m in "${live_mirrors[@]}"; do [[ "${m}" == "${pinned_from}" ]] || printf 'Server = %s\n' "${m}"; done
  } > /etc/pacman.d/mirrorlist.cicada
  mv /etc/pacman.d/mirrorlist.cicada /etc/pacman.d/mirrorlist
fi

"${ROOT}/iso/assemble-profile.sh"

# malloc: prefer cicada-malloc from the product pacstrap repo; otherwise bake
# the .so into airootfs (rsync / legacy path).
if compgen -G "${PROFILE}/cicada-product-repo/cicada-malloc-*.pkg.tar.*" >/dev/null 2>&1; then
  echo "==> hardened_malloc via cicada-malloc package (pacstrap)"
elif [[ -x "${ROOT}/scripts/build-hardened-malloc.sh" ]]; then
  "${ROOT}/scripts/build-hardened-malloc.sh" "${PROFILE}/airootfs" || \
    echo "==> hardened_malloc build skipped (ISO still boots; preload is a no-op)"
fi

# Official Helium tarball (hash-pinned). Fail the ISO if this cannot land —
# Chromium is no longer the product browser. Channel ships cicada-helium for
# post-install upgrades; the ISO still embeds /opt/helium for first boot.
"${ROOT}/scripts/install-helium.sh" "${PROFILE}/airootfs"

# Official Chocolate Doom + Freedoom (hash-pinned). Tirimid item 6 — required.
"${ROOT}/scripts/install-doom.sh" "${PROFILE}/airootfs"

# Prove Helium + wallpaper landed before the long pacstrap (fail fast).
helium_bin=""
for cand in \
  "${PROFILE}/airootfs/opt/helium/helium" \
  "${PROFILE}/airootfs/opt/helium/chrome" \
  "${PROFILE}/airootfs/opt/helium/helium-wrapper"
do
  if [[ -x "${cand}" ]]; then
    helium_bin="${cand}"
    break
  fi
done
[[ -n "${helium_bin}" ]] || {
  echo "error: Helium not executable in airootfs after install-helium.sh" >&2
  ls -la "${PROFILE}/airootfs/opt/helium" 2>&1 | head -20 >&2 || true
  exit 1
}
wall="${PROFILE}/airootfs/usr/share/cicada/wallpapers/cicada-3301.png"
wall_src="${ROOT}/packages/cicada-shell/files/usr/share/cicada/wallpapers/cicada-3301.png"
if [[ ! -f "${wall}" && -f "${wall_src}" ]]; then
  # Pacman-owned product path: wallpaper arrives via cicada-shell pacstrap;
  # stage a copy so this preflight (before mkarchiso) still fails closed.
  mkdir -p "$(dirname "${wall}")"
  cp -a "${wall_src}" "${wall}"
fi
[[ -f "${wall}" ]] || {
  echo "error: wallpaper missing at ${wall}" >&2
  exit 1
}
grep -q 'cicada-wallpaper' "${PROFILE}/airootfs/etc/skel/.config/hypr/hyprland.conf" \
  || grep -q 'cicada-wallpaper' "${PROFILE}/airootfs/home/cicada/.config/hypr/hyprland.conf" \
  || echo "==> warning: cicada-wallpaper not in hyprland.conf (desk may stay void)"
echo "==> preflight OK: Helium=$(basename "${helium_bin}") wallpaper=$(basename "${wall}")"

echo "==> mkarchiso  work=${WORK}/mkarchiso  out=${OUT}"
rm -rf "${WORK}/mkarchiso"
mkdir -p "${WORK}/mkarchiso"

# iso/reproducible-bin/xorriso clamps the ISO staging tree's mtimes to
# SOURCE_DATE_EPOCH before the real xorriso runs (see the shim for why).
MKARCHISO_PATH="${ROOT}/iso/reproducible-bin:${PATH}"

run_mkarchiso() {
  local MKARCHISO=(mkarchiso -v -w "${WORK}/mkarchiso" -o "${OUT}" "${PROFILE}")
  if [[ "${EUID}" -ne 0 ]]; then
    # sudo resets PATH (secure_path) and drops SOURCE_DATE_EPOCH; pass both.
    MKARCHISO=(sudo env PATH="${MKARCHISO_PATH}" ${SOURCE_DATE_EPOCH:+SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}"} "${MKARCHISO[@]}")
  else
    MKARCHISO=(env PATH="${MKARCHISO_PATH}" "${MKARCHISO[@]}")
  fi
  "${MKARCHISO[@]}"
}

# Under qemu-amd64, a killed prior pacstrap can leave the work volume poisoned
# even after rm -rf; one clean retry covers the perl/desc abort class.
if ! run_mkarchiso; then
  echo "==> mkarchiso failed — scrubbing work and retrying once"
  rm -rf "${WORK}/mkarchiso"
  mkdir -p "${WORK}/mkarchiso"
  # Drop any stale locks from a crashed privileged mount
  sleep 2
  run_mkarchiso
fi

# Persist pacman pkg cache → local cicada-stable repo (next assemble embeds it).
PKG_CACHE=""
for cand in \
  "${WORK}/mkarchiso/x86_64/airootfs/var/cache/pacman/pkg" \
  "${WORK}/mkarchiso/airootfs/var/cache/pacman/pkg" \
  "${WORK}/mkarchiso/pacman/pkg" \
  /var/cache/pacman/pkg
do
  # mkarchiso pacstraps with -c, so the packages land in the *builder's* cache
  # (a persistent docker volume), not in the airootfs. The airootfs paths are
  # kept first for older archiso behaviour; /var/cache/pacman/pkg is the one
  # that actually has anything today.
  if [[ -d "${cand}" ]] && compgen -G "${cand}/*.pkg.tar.*" >/dev/null 2>&1; then
    PKG_CACHE="${cand}"
    break
  fi
done
if [[ -n "${PKG_CACHE}" ]]; then
  echo "==> channel repo from ${PKG_CACHE}"
  mkdir -p "${OUT}/channel-repo"
  if [[ -x "${ROOT}/scripts/channel-build-repo.sh" ]] || [[ -f "${ROOT}/scripts/channel-build-repo.sh" ]]; then
    bash "${ROOT}/scripts/channel-build-repo.sh" "${PKG_CACHE}" "${OUT}/channel-repo" || \
      echo "==> channel-build-repo skipped (non-fatal)"
    # No tree copy into channel/repo: /src is mounted read-only in the builder,
    # so it never worked, and the repo is ~2 GiB — it belongs in out/ (published
    # to the channel-latest release), not in the git tree or on the ISO.
  fi
else
  echo "==> no pacman pkg cache found under ${WORK}/mkarchiso (channel repo deferred)"
fi

echo "==> ISO(s):"
ls -lh "${OUT}"/*.iso

# Always point flash scripts / humans at the newest image (same-day rebuilds
# overwrite cicada-YYYY.MM.DD-x86_64.iso; the symlink tracks whichever won).
newest="$(ls -1t "${OUT}"/cicada-*.iso 2>/dev/null | grep -v 'cicada-latest' | head -1 || true)"
if [[ -n "${newest}" ]]; then
  ln -sfn "$(basename "${newest}")" "${OUT}/cicada-latest-x86_64.iso"
  echo "==> latest -> ${OUT}/cicada-latest-x86_64.iso -> $(basename "${newest}")"
  ls -lh "${newest}" "${OUT}/cicada-latest-x86_64.iso"
fi
