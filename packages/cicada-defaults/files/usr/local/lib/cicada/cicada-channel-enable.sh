#!/usr/bin/env bash
# Ensure [cicada-stable] appears before Arch core/extra in pacman.conf.
set -euo pipefail
CONF="${1:-/etc/pacman.conf}"
SNIPPET=/etc/pacman.d/cicada-repos.conf

mkdir -p "$(dirname "${SNIPPET}")" /var/cache/cicada/repo

cat > "${SNIPPET}" <<'EOF'
# Cicada channel — local signed pin. Prefer before Arch extras.
# Empty dir is fine: pacman falls through to core/extra when this Server has no db.
[cicada-stable]
SigLevel = PackageOptional DatabaseOptional
Server = file:///var/cache/cicada/repo
EOF

if [[ ! -f "${CONF}" ]]; then
  echo "cicada-channel-enable: ${CONF} missing — wrote snippet only" >&2
  exit 0
fi

if grep -q '\[cicada-stable\]' "${CONF}"; then
  exit 0
fi

# Insert Include before the first [core] / [extra] repository block.
tmp="$(mktemp)"
python3 - "${CONF}" "${tmp}" <<'PY'
import sys
path, out = sys.argv[1], sys.argv[2]
text = open(path).read()
include = "\n# Cicada channel (policy OS pin)\nInclude = /etc/pacman.d/cicada-repos.conf\n"
if "[cicada-stable]" in text or "cicada-repos.conf" in text:
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
