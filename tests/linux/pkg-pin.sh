#!/usr/bin/env bash
# cicada-pkg-helper must install extras from the channel snapshot's own day.
#
# The base system is a dated snapshot and Arch's live mirrors are weeks past
# it, so `pacman -Sy <pkg>` against them is a partial upgrade — the failure
# tests/linux.sh itself documents for libnftnl. The helper points core/extra at
# the Arch Linux Archive for the pin's date instead. What matters here is which
# config and which flags pacman is handed, so pacman is a stub that records
# them: no network, and the assertion is on the decision rather than on a
# mirror being up.
set -uo pipefail
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }
HELPER=/src/packages/cicada-defaults/files/usr/local/bin/cicada-pkg-helper

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin" /etc/cicada
cat > "${tmp}/bin/pacman" <<STUB
#!/bin/bash
printf '%s\n' "\$*" > "${tmp}/args"
conf=/etc/pacman.conf
while [[ \$# -gt 0 ]]; do [[ "\$1" == --config ]] && conf="\$2"; shift; done
cp "\${conf}" "${tmp}/conf"
STUB
chmod +x "${tmp}/bin/pacman"
run() { PATH="${tmp}/bin:${PATH}" bash "${HELPER}" "$@" >"${tmp}/out" 2>&1; }

cat > /etc/pacman.conf <<'CONF'
[options]
Architecture = auto
Include = /etc/pacman.d/cicada-repos.conf
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
  Include = /etc/pacman.d/mirrorlist
CONF
cp /etc/pacman.conf "${tmp}/orig"

echo cicada-stable-2026.08.20 > /etc/cicada/channel
run install htop || die "curated install exited non-zero: $(cat "${tmp}/out")"
want='Server = https://archive.archlinux.org/repos/2026/08/20/$repo/os/$arch'
[[ "$(grep -cxF "${want}" "${tmp}/conf")" -eq 2 ]] \
  && say "core and extra point at the archive for the pin's date" \
  || die "pinned config is wrong: $(cat "${tmp}/conf")"
grep -q 'mirrorlist' "${tmp}/conf" && die "a live mirrorlist Include survived" \
  || say "no live mirrorlist left in the pinned config"
grep -qxF 'Include = /etc/pacman.d/cicada-repos.conf' "${tmp}/conf" \
  && say "[cicada-stable] include is untouched" || die "channel include was rewritten"
grep -q -- '-Syy' "${tmp}/args" && say "forces the dated database (-Syy)" \
  || die "single -y keeps a newer live database: $(cat "${tmp}/args")"
cmp -s /etc/pacman.conf "${tmp}/orig" && say "/etc/pacman.conf itself is not modified" \
  || die "/etc/pacman.conf was edited"
[[ -z "$(ls /run/cicada/pacman-pinned.* 2>/dev/null)" ]] && say "throwaway config removed" \
  || die "pinned config left behind in /run/cicada"

run install-any some-pkg || die "install-any exited non-zero"
grep -q -- '--config /run/cicada/pacman-pinned' "${tmp}/args" \
  && say "install-any takes the same pinned path" || die "install-any went to live mirrors"

# No date in the pin: nothing to match, so say so and fall back — never a
# silent live install, never a refusal to install git.
echo unknown > /etc/cicada/channel
run install htop || die "undated pin must still install"
grep -q 'partial upgrade' "${tmp}/out" && say "undated pin warns out loud" \
  || die "undated pin fell back silently"
grep -q -- '--config' "${tmp}/args" && die "undated pin still used a pinned config" \
  || say "undated pin uses the system config"

# Hand-written Server lines: nothing to rewrite, so the result must not be
# passed off as pinned.
echo cicada-stable-2026.08.20 > /etc/cicada/channel
printf '[options]\n[core]\nServer = https://mirror.example/$repo/os/$arch\n' > /etc/pacman.conf
run install htop || die "custom-mirror config must still install"
grep -q 'partial upgrade' "${tmp}/out" && say "unrewritable config warns out loud" \
  || die "unrewritable config was treated as pinned"

[[ "${fail}" -eq 0 ]] || exit 1
