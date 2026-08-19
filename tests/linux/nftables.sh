#!/usr/bin/env bash
# Runs INSIDE the privileged Linux container. Loads Cicada's rulesets into a
# real kernel and asks the kernel what it got — not the file what it says.
set -uo pipefail
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }
SRC=/src

echo "==> baseline ruleset loads into a real kernel"
if nft -f "${SRC}/packages/cicada-defaults/files/etc/nftables.d/cicada-baseline.nft" 2>/tmp/nfterr; then
  say "cicada-baseline.nft accepted by nft $(nft --version | awk '{print $2}')"
else
  die "baseline ruleset rejected: $(cat /tmp/nfterr)"
fi

# Everything below reads the KERNEL's rendering of the loaded ruleset. A typo
# that nft accepts but that means something else still shows up here.
live="$(nft -a list table inet cicada 2>/dev/null)"
grep -qE 'hook input .*policy drop' <<<"${live}" \
  && say "input policy is drop (kernel's own view)" \
  || die "input chain is not default-deny: $(grep -m1 'hook input' <<<"${live}")"
grep -qE 'hook forward .*policy drop' <<<"${live}" \
  && say "forward policy is drop" || die "forward chain is not drop"

echo "==> kill switch ruleset loads and has no conntrack escape"
if nft -f "${SRC}/packages/cicada-defaults/files/etc/cicada/killswitch.nft" 2>/tmp/nfterr; then
  say "killswitch.nft accepted by the kernel"
else
  die "killswitch rejected: $(cat /tmp/nfterr)"
fi
ks="$(nft list table inet cicada_ks 2>/dev/null)"
grep -qE 'hook output .*policy drop' <<<"${ks}" \
  && say "killswitch output policy is drop" || die "killswitch output is not drop"

# The claim this whole file exists to protect, from README: "VPN kill switch
# with no `ct established` exemption in the output chain". Read it out of the
# kernel's output chain specifically — the input chain legitimately has one.
out_chain="$(awk '/chain output/,/^[[:space:]]*}/' <<<"${ks}")"
if grep -q 'ct state' <<<"${out_chain}"; then
  die "killswitch OUTPUT chain has a conntrack exemption: $(grep 'ct state' <<<"${out_chain}")"
else
  say "no ct state rule in the output chain — pre-tunnel flows cannot survive"
fi
in_chain="$(awk '/chain input/,/^[[:space:]]*}/' <<<"${ks}")"
grep -q 'ct state established' <<<"${in_chain}" \
  && say "input chain keeps its established/related return path" \
  || die "input chain lost its return path — tunnel sessions break on rekey"

echo "==> the kill switch actually blocks egress"
# Clear the rulesets loaded above out of THIS netns first. Inspecting the kill
# switch left its output chain (policy drop) active here, which blocks the reply
# side of the test below — and a setup that cannot reach anything would make
# every "traffic was blocked" assertion pass for the wrong reason.
nft flush ruleset
# Behavioural, not textual. In a fresh netns with a route out, confirm traffic
# leaves; load the kill switch; confirm it stops. There is no wg0 here, so
# every accept rule in the output chain is inapplicable and the policy governs.
ip netns add ks 2>/dev/null
ip link add ksa type veth peer name ksb 2>/dev/null
ip link set ksb netns ks
ip addr add 10.77.0.1/24 dev ksa; ip link set ksa up
ip -n ks addr add 10.77.0.2/24 dev ksb; ip -n ks link set ksb up; ip -n ks link set lo up
ip -n ks route add default via 10.77.0.1

if ip netns exec ks ping -c1 -W2 10.77.0.1 >/dev/null 2>&1; then
  say "baseline: the netns can reach its gateway"
else
  die "test setup broken — no connectivity before the kill switch"
fi

ip netns exec ks nft -f "${SRC}/packages/cicada-defaults/files/etc/cicada/killswitch.nft"
if ip netns exec ks ping -c1 -W2 10.77.0.1 >/dev/null 2>&1; then
  die "KILL SWITCH LEAKS — traffic still left the box with the switch armed"
else
  say "with the switch armed and no wg0, egress is dropped"
fi

# The regression the ruleset comment is specifically written to prevent: a flow
# that existed BEFORE the switch came up must not be waved through afterwards.
#
# This has to be a real TCP connection, and conntrack has to already be engaged
# when it is opened. A ping after `nft flush ruleset` does not work: nftables
# only turns conntrack on when some rule references `ct`, so with an empty
# ruleset the flow is never tracked, there is nothing for an exemption to match,
# and the test passes whether or not the bug is present. It was written that way
# first and proved exactly nothing.
ip netns exec ks nft flush ruleset
ip netns exec ks nft -f "${SRC}/packages/cicada-defaults/files/etc/nftables.d/cicada-baseline.nft"

python3 - <<'LISTENER' &
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("10.77.0.1", 9999)); s.listen(1)
c, _ = s.accept()
c.settimeout(6)
got = b""
try:
    while True:
        b = c.recv(64)
        if not b:
            break
        got += b
except Exception:
    pass
open("/tmp/received.txt", "wb").write(got)
LISTENER
listener=$!
sleep 1

ip netns exec ks bash -c '
  exec 3<>/dev/tcp/10.77.0.1/9999 || exit 1
  echo before >&3
  sleep 1
  nft -f "'"${SRC}"'/packages/cicada-defaults/files/etc/cicada/killswitch.nft"
  echo after >&3
  sleep 2
' 2>/dev/null
wait "${listener}" 2>/dev/null || true
received="$(cat /tmp/received.txt 2>/dev/null || true)"

if ! grep -q before <<<"${received}"; then
  die "setup broken — the connection never carried data before the switch"
elif grep -q after <<<"${received}"; then
  die "KILL SWITCH LEAKS — a flow opened before the switch kept sending after it"
else
  say "an established TCP flow stops the moment the switch arms (ct exemption absent)"
fi

ip netns del ks 2>/dev/null
ip link del ksa 2>/dev/null

[[ "${fail}" -eq 0 ]] || { echo "NFTABLES (linux) FAILED"; exit 1; }
echo "nftables ok"
