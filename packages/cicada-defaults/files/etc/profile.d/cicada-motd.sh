# Show Cicada banner once per login shell on tty
if [[ -z "${CICADA_MOTD_SHOWN:-}" && -t 1 && "$(id -u)" -ne 0 ]]; then
  export CICADA_MOTD_SHOWN=1
  [[ -x /usr/local/bin/cicada-firstboot ]] && /usr/local/bin/cicada-firstboot 2>/dev/null || true
fi