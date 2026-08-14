#!/usr/bin/env bash
# Ensure [cicada-stable] appears before Arch core/extra in pacman.conf.
# Users update via cicada-update — not raw Arch mirrors as the product path.
set -euo pipefail
CONF="${1:-/etc/pacman.conf}"
SNIPPET=/etc/pacman.d/cicada-repos.conf
MIRROR_FILE=/etc/cicada/channel-mirror.url

mkdir -p "$(dirname "${SNIPPET}")" /var/cache/cicada/repo /etc/cicada

# Hosted mirror (https) wins when configured; else local ISO-embedded repo.
servers=()
if [[ -f "${MIRROR_FILE}" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [[ -n "${line}" ]] && servers+=("Server = ${line}")
  done < "${MIRROR_FILE}"
fi
servers+=("Server = file:///var/cache/cicada/repo")

# Strict signatures when the Cicada pubkey is on disk; optional until first sign.
sig="PackageOptional DatabaseOptional"
if [[ -f /etc/pacman.d/cicada-stable-key.gpg ]] || [[ -f /etc/pacman.d/cicada-stable-key.asc ]]; then
  sig="Required"
fi

{
  echo "# Cicada channel — prefer before Arch core/extra."
  echo "# Product updates: cicada-update. Do not treat raw Arch rolling as Cicada."
  echo "[cicada-stable]"
  echo "SigLevel = ${sig}"
  printf '%s\n' "${servers[@]}"
} > "${SNIPPET}"

# Default mirror stub (commented) so operators know where to put the URL.
if [[ ! -f "${MIRROR_FILE}" ]]; then
  cat > "${MIRROR_FILE}.example" <<'EOF'
# Uncomment / replace with the hosted cicada-stable root (must serve pacman db).
# https://github.com/kpresler12/Cicada.OS/releases/download/channel-latest
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
