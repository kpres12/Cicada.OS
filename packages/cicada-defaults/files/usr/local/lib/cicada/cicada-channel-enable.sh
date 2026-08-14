#!/usr/bin/env bash
# Ensure [cicada-stable] appears before Arch core/extra in pacman.conf.
# Users update via cicada-update — not raw Arch mirrors as the product path.
set -euo pipefail
CONF="${1:-/etc/pacman.conf}"
SNIPPET=/etc/pacman.d/cicada-repos.conf
MIRROR_FILE=/etc/cicada/channel-mirror.url

mkdir -p "$(dirname "${SNIPPET}")" /var/cache/cicada/repo /etc/cicada

# Adding the key to the keyring is not the same as trusting it. Without a local
# signature pacman reports the database as having unknown trust and refuses it
# under SigLevel=Required — which looks exactly like a tampered mirror. Take the
# fingerprint from the key file itself rather than parsing --list-keys output,
# whose layout puts the fingerprint above the uid, not below it.
for keyfile in /etc/pacman.d/cicada-stable-key.gpg /etc/pacman.d/cicada-stable-key.asc; do
  [[ -f "${keyfile}" ]] || continue
  command -v pacman-key >/dev/null 2>&1 || break
  pacman-key --add "${keyfile}" >/dev/null 2>&1 || true
  fpr="$(gpg --with-colons --show-keys "${keyfile}" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
  if [[ -n "${fpr}" ]]; then
    pacman-key --lsign-key "${fpr}" >/dev/null 2>&1 || true
  fi
  break
done

# Hosted mirror (https) wins when configured; else local ISO-embedded repo.
servers=()
remote=0
if [[ -f "${MIRROR_FILE}" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [[ -z "${line}" ]] && continue
    servers+=("Server = ${line}")
    [[ "${line}" == http://* || "${line}" == https://* ]] && remote=1
  done < "${MIRROR_FILE}"
fi

# Only offer the local repo when it actually holds a database. Listing a file://
# Server for an empty directory makes `pacman -Sy` fail outright ("could not
# open file … cicada-stable.db"), which takes cicada-update down with it — the
# ISO ships that directory empty by design.
if compgen -G "/var/cache/cicada/repo/cicada-stable.db*" >/dev/null 2>&1; then
  servers+=("Server = file:///var/cache/cicada/repo")
fi

# Fail closed on hosted mirrors: never PackageOptional over the network.
# Local file:// may stay optional until the first signed channel build ships a key.
sig="PackageOptional DatabaseOptional"
if [[ -f /etc/pacman.d/cicada-stable-key.gpg ]] || [[ -f /etc/pacman.d/cicada-stable-key.asc ]]; then
  sig="Required"
elif [[ "${remote}" -eq 1 ]]; then
  echo "cicada-channel-enable: ERROR hosted mirror without pubkey — not enabling remote Server" >&2
  # Drop remote servers; keep file:// only so we never instruct pacman to trust https unsigned.
  servers=("Server = file:///var/cache/cicada/repo")
  remote=0
fi

# A [cicada-stable] section with no Server makes every pacman call fail with
# "repository 'cicada-stable' has no servers configured". When there is nowhere
# to sync from, write the section out commented instead — pacman stays usable
# and cicada-update reports honestly that there is no channel yet.
if [[ "${#servers[@]}" -eq 0 ]]; then
  {
    echo "# Cicada channel — no mirror configured and no local repo present."
    echo "# Put the hosted root in ${MIRROR_FILE}, then re-run this script."
    echo "#[cicada-stable]"
    echo "#SigLevel = ${sig}"
  } > "${SNIPPET}"
else
  {
    echo "# Cicada channel — prefer before Arch core/extra."
    echo "# Product updates: cicada-update. Do not treat raw Arch rolling as Cicada."
    echo "[cicada-stable]"
    echo "SigLevel = ${sig}"
    printf '%s\n' "${servers[@]}"
  } > "${SNIPPET}"
fi

# Default mirror stub (commented) so operators know where to put the URL.
if [[ ! -f "${MIRROR_FILE}" ]]; then
  cat > "${MIRROR_FILE}.example" <<'EOF'
# Uncomment / replace with the hosted cicada-stable root (must serve pacman db).
# https://github.com/kpres12/Cicada.OS/releases/download/channel-latest
# https://mirror.example/cicada-stable/\$repo/\$arch
EOF
fi

if [[ ! -f "${CONF}" ]]; then
  echo "cicada-channel-enable: ${CONF} missing — wrote snippet only" >&2
  exit 0
fi

if grep -q 'cicada-repos.conf' "${CONF}"; then
  echo "cicada-channel-enable: snippet refreshed (${sig})"
  exit 0
fi

tmp="$(mktemp)"
python3 - "${CONF}" "${tmp}" <<'PY'
import sys
path, out = sys.argv[1], sys.argv[2]
text = open(path).read()
include = "\n# Cicada channel (policy OS pin)\nInclude = /etc/pacman.d/cicada-repos.conf\n"
if "cicada-repos.conf" in text:
    open(out, "w").write(text)
    raise SystemExit(0)
lines = text.splitlines(True)
out_lines = []
inserted = False
for line in lines:
    if not inserted and line.startswith("[core]"):
        out_lines.append(include)
        inserted = True
    out_lines.append(line)
if not inserted:
    out_lines.append(include)
open(out, "w").write("".join(out_lines))
PY
mv "${tmp}" "${CONF}"
echo "cicada-channel-enable: [cicada-stable] preferred in ${CONF}"
