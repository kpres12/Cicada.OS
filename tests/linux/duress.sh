#!/usr/bin/env bash
# The session duress credential: does the right password wipe, and — far more
# important — does everything else NOT wipe.
#
# This is the highest-stakes decision in the OS. A false positive destroys the
# disk of someone who fat-fingered their password; a false negative leaves
# somebody under coercion believing a wipe happened when it did not. It ran on
# the "needs the machine" list because it is a PAM hook, but PAM is not what
# decides — this script is, and it is just stdin, a hash, and a comparison.
#
# Nothing destructive runs: cryptsetup and dd are stubbed on PATH, the target
# device is a temp file, and the sysrq reset is redirected. The stubs record
# that they were called, which is the whole verdict.
set -uo pipefail
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }
SRC=/src
CHECK="${SRC}/packages/cicada-defaults/files/usr/local/bin/cicada-duress-check"

tmp="$(mktemp -d)"
stub="${tmp}/stub"; mkdir -p "${stub}"
for c in dd logger systemctl; do
  cat > "${stub}/${c}" <<STUB
#!/bin/sh
echo "${c} \$*" >> "${tmp}/called"
exit 0
STUB
  chmod 755 "${stub}/${c}"
done
# cryptsetup needs to answer the device-discovery call, not just record it —
# otherwise the script finds no device, skips the whole wipe block, and the
# test's only evidence of "it wiped" would be the discovery call itself. That
# is what the first version of this file did, and it reported a pass.
cat > "${stub}/cryptsetup" <<STUB
#!/bin/sh
echo "cryptsetup \$*" >> "${tmp}/called"
if [ "\$1" = "status" ]; then
  echo "  device:  ${tmp}/fakedev"
fi
exit 0
STUB
chmod 755 "${stub}/cryptsetup"
export PATH="${stub}:${PATH}"

SECRET='correct horse battery staple'
printf '%s' "${SECRET}" | sha256sum | awk '{print $1}' > "${tmp}/hash"
: > "${tmp}/fakedev"
cat > "${tmp}/install.env" <<ENV
CICADA_LUKS_UUID=deadbeef-0000-0000-0000-000000000000
ENV

run() {
  : > "${tmp}/called"
  : > "${tmp}/sysrq"
  printf '%s' "$1" | env \
    CICADA_DURESS_HASHFILE="${2:-${tmp}/hash}" \
    CICADA_DURESS_INSTALL_ENV="${tmp}/install.env" \
    CICADA_DURESS_SYSRQ="${tmp}/sysrq" \
    PATH="${stub}:${PATH}" \
    bash "${CHECK}" >/dev/null 2>&1
  echo "$?"
}
wiped() { grep -qE 'cryptsetup (luksErase|erase)' "${tmp}/called" 2>/dev/null; }
reset_fired() { [[ -s "${tmp}/sysrq" ]]; }

echo "==> a wrong password must not wipe"
for wrong in "wrong" "" "correct horse battery stapl" "correct horse battery stapleX" "CORRECT HORSE BATTERY STAPLE"; do
  rc="$(run "${wrong}")"
  if wiped; then
    die "WIPED on a non-matching input: '${wrong}'"
  fi
  [[ "${rc}" == 0 ]] || die "non-zero exit (${rc}) on '${wrong}' — pam_exec would surface it"
done
say "five near-miss inputs, including a truncation and a case change: no wipe"
say "every one exited 0 — indistinguishable from the module not being installed"

echo "==> no hash file configured means the feature is simply off"
rc="$(run "${SECRET}" "${tmp}/does-not-exist")"
wiped && die "wiped with no duress credential enrolled"
[[ "${rc}" == 0 ]] || die "non-zero exit with no hash file"
say "unenrolled machine ignores even a correct-looking secret"

echo "==> an empty hash file does not match the empty string"
: > "${tmp}/emptyhash"
rc="$(run "" "${tmp}/emptyhash")"
wiped && die "empty hash file matched empty input — every wrong password would wipe"
say "an empty/truncated hash file cannot match anything"

echo "==> the correct password does wipe"
rc="$(run "${SECRET}")"
if wiped; then
  say "keyslots erased: $(grep -m1 -E 'cryptsetup (luksErase|erase)' "${tmp}/called")"
else
  die "the duress credential did NOT trigger the wipe"
fi
grep -q 'dd ' "${tmp}/called" && say "header overwrite followed the keyslot erase" \
  || die "no dd — the LUKS header was left intact"
reset_fired && say "the hard reset fired (redirected here, not to the real sysrq trigger)" \
  || die "no reset — the volume key would stay live in DRAM"
[[ "${rc}" == 0 ]] || die "exited ${rc} on a match; pam_exec optional expects 0"

echo "==> KNOWN: surrounding whitespace is stripped, at enrolment and at check"
# Not asserted as good — asserted so it is written down and cannot change
# silently. bash/ash `read` splits on IFS, which strips leading and trailing
# whitespace. cicada-duress-enroll reads the secret the same way, so enrolment
# and check agree and the credential works; the consequence is that the set of
# inputs that trigger an irreversible wipe is slightly wider than the enrolled
# string — "secret ", " secret" and "secret" are one credential.
#
# Narrowing it means `IFS= read` in cicada-duress-enroll AND in the initramfs
# hook (usr/lib/initcpio/hooks/cicada-crypt), because all three must hash the
# same bytes. That is a change to the boot unlock path and is deliberately not
# made here; this test exists so the behaviour is a documented property rather
# than a surprise.
run "${SECRET} " >/dev/null
if wiped; then
  say "trailing whitespace still matches (documented consequence of read+IFS)"
else
  die "whitespace handling changed — enrolment and check may now disagree, \
which would mean the duress credential silently stops working"
fi

echo "==> a trailing newline on the enrolled hash is tolerated"
printf '%s' "${SECRET}" | sha256sum | awk '{print $1}' > "${tmp}/hash_nl"
printf '\n' >> "${tmp}/hash_nl"
run "${SECRET}" "${tmp}/hash_nl" >/dev/null
wiped && say "whitespace in the hash file does not break enrolment" \
  || die "a trailing newline in the hash file silently disabled the wipe"


# ---------------------------------------------------------------------------
echo "==> THE LOCK SCREEN: the hook runs unprivileged and must still reach a wipe"
#
# Everything above ran as root, which is the `sudo` path — sudo is setuid, so
# pam_exec's `seteuid` really does hand the hook euid 0. hyprlock is NOT setuid
# (Arch ships it 0755; it authenticates through unix_chkpwd like any other
# unprivileged program), so at the lock screen the hook runs as the desktop
# user. It could not read the 0400 verifier, could not erase a keyslot and could
# not write sysrq-trigger — and it exited 0, which is also what a wrong guess
# does. The session duress credential was inert in the one room it was written
# for, and a structural test that greps for "seteuid" passes on that.
#
# So this models the real thing: a root-owned 0400 verifier, a root listener on
# the socket, and the check invoked as an unprivileged uid.
# ---------------------------------------------------------------------------
tuser=cicadatest
id -u "${tuser}" >/dev/null 2>&1 || useradd -M -N -g users -G wheel -s /bin/bash "${tuser}" 2>/dev/null
tuid="$(id -u "${tuser}")"; tgid="$(id -g "${tuser}")"

chmod 755 "${tmp}"
install -m 400 -o root -g root "${tmp}/hash" "${tmp}/hash_root"

if su -s /bin/sh "${tuser}" -c "cat '${tmp}/hash_root'" >/dev/null 2>&1; then
  die "the verifier is readable by the desktop user — it must be 0400 root"
else
  say "the unprivileged side genuinely cannot read the 0400 verifier"
fi

sockdir="${tmp}/run"; mkdir -p "${sockdir}"; chmod 755 "${sockdir}"
SOCKPATH="${sockdir}/duress.sock"

cat > "${tmp}/listener.py" <<'LISTENER'
import os, socket, subprocess, sys
path = os.environ["SOCKPATH"]
try: os.unlink(path)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path); s.listen(4)
os.chmod(path, 0o660)                      # product uses 0660 root:wheel
import grp
try: os.chown(path, 0, grp.getgrnam("wheel").gr_gid)
except Exception: pass
open(os.environ["READY"], "w").write("1")
while True:
    conn, _ = s.accept()
    # systemd Accept=yes hands the connection over as stdin. Same here.
    subprocess.run(["bash", os.environ["CHECK"], "--from-socket"],
                   stdin=conn, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   env={**os.environ, "PATH": os.environ["STUBPATH"]})
    conn.close()
LISTENER

start_listener() {
  rm -f "${tmp}/ready" "${tmp}/called" "${tmp}/sysrq"
  : > "${tmp}/called"; : > "${tmp}/sysrq"
  SOCKPATH="${SOCKPATH}" READY="${tmp}/ready" CHECK="${CHECK}" \
  STUBPATH="${stub}:${PATH}" \
  CICADA_DURESS_HASHFILE="${tmp}/hash_root" \
  CICADA_DURESS_INSTALL_ENV="${tmp}/install.env" \
  CICADA_DURESS_SYSRQ="${tmp}/sysrq" \
    python3 "${tmp}/listener.py" >/dev/null 2>&1 &
  listener_pid=$!
  for _ in $(seq 1 100); do [[ -f "${tmp}/ready" ]] && break; sleep 0.05; done
  [[ -f "${tmp}/ready" ]] || { die "test listener never came up"; return 1; }
}
stop_listener() { kill "${listener_pid}" 2>/dev/null || true; wait "${listener_pid}" 2>/dev/null || true; }

# The unprivileged half: exactly what pam_exec would run at the lock screen.
as_user() {
  printf '%s' "$1" | setpriv --reuid "${tuid}" --regid "${tgid}" --groups "$(getent group wheel | cut -d: -f3)" \
    env CICADA_DURESS_SOCK="${SOCKPATH}" \
        CICADA_DURESS_HASHFILE="${tmp}/hash_root" \
        PATH="/usr/bin:/bin" \
    bash "${CHECK}" >/dev/null 2>&1
  echo "$?"
}

if start_listener; then
  rc="$(as_user "${SECRET}")"
  sleep 0.5
  if wiped; then
    say "lock-screen duress reached the wipe through the privileged socket"
  else
    die "THE LOCK SCREEN STILL DOES NOT WIPE — session duress is inert where it matters"
  fi
  reset_fired && say "the hard reset fired from the privileged side" \
    || die "no reset: the volume key would stay live in DRAM"
  [[ "${rc}" == 0 ]] || die "unprivileged hook exited ${rc}; pam_exec optional expects 0"
  stop_listener
fi

echo "==> a wrong password over the socket still must not wipe"
if start_listener; then
  rc="$(as_user "not the duress password")"
  sleep 0.5
  wiped && die "WIPED on a wrong password via the socket" \
    || say "wrong password forwarded, compared as root, no wipe"
  [[ "${rc}" == 0 ]] || die "wrong password exited ${rc}, not 0"
  stop_listener
fi

echo "==> with no handler present the hook must not hang or fake success"
: > "${tmp}/called"; : > "${tmp}/sysrq"
start="$(date +%s)"
# --groups is not optional: setpriv refuses to change uid/gid without one of
# --clear-groups/--keep-groups/--groups, and without it setpriv's own exit 1
# gets read as the hook's exit code. Use the same invocation as as_user().
rc="$(printf '%s' "${SECRET}" | setpriv --reuid "${tuid}" --regid "${tgid}" \
       --groups "$(getent group wheel | cut -d: -f3)" \
       env CICADA_DURESS_SOCK="${tmp}/nonexistent.sock" \
           CICADA_DURESS_HASHFILE="${tmp}/hash_root" PATH="/usr/bin:/bin" \
       bash "${CHECK}" >/dev/null 2>&1; echo $?)"
elapsed=$(( $(date +%s) - start ))
wiped && die "wiped with no privileged handler configured" \
  || say "no handler: no wipe"
[[ "${rc}" == 0 ]] || die "exited ${rc} with no handler; must be 0"
(( elapsed <= 8 )) && say "returned in ${elapsed}s — a PAM hook that blocks is a lock screen that stops taking input" \
  || die "took ${elapsed}s with no handler: the lock screen would appear frozen"

rm -rf "${tmp}"
[[ "${fail}" -eq 0 ]] || { echo "DURESS (linux) FAILED"; exit 1; }
echo "duress ok"
