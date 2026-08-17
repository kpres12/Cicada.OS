#!/usr/bin/env bash
# The sandbox syscall filter, proved rather than asserted.
#
# tests/here.sh can only check that cicada-run says --seccomp. This checks that
# the program cicada-seccomp-gen.sh emits is a valid seccomp filter that returns
# the right verdict for the right syscall — by decoding it and running the same
# instruction machine the kernel does. On Linux it then loads it for real.
#
# Run: tests/seccomp.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/cicada-seccomp-gen.sh"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# A synthetic uapi header with the real x86_64 numbers for the syscalls under
# test, so this suite runs on the Mac and does not silently pass by resolving
# nothing. The generator's contract is "read the numbers from the header", and
# that contract is exactly what is being exercised here.
cat > "${tmp}/unistd_64.h" <<'EOF'
#define __NR_read 0
#define __NR_write 1
#define __NR_ptrace 101
#define __NR_syslog 103
#define __NR_uselib 134
#define __NR_modify_ldt 154
#define __NR_acct 163
#define __NR_swapon 167
#define __NR_swapoff 168
#define __NR_iopl 172
#define __NR_ioperm 173
#define __NR_init_module 175
#define __NR_delete_module 176
#define __NR_quotactl 179
#define __NR_mbind 237
#define __NR_set_mempolicy 238
#define __NR_get_mempolicy 239
#define __NR_kexec_load 246
#define __NR_add_key 248
#define __NR_request_key 249
#define __NR_keyctl 250
#define __NR_migrate_pages 256
#define __NR_move_pages 279
#define __NR_perf_event_open 298
#define __NR_name_to_handle_at 303
#define __NR_open_by_handle_at 304
#define __NR_process_vm_readv 310
#define __NR_process_vm_writev 311
#define __NR_finit_module 313
#define __NR_kexec_file_load 320
#define __NR_bpf 321
#define __NR_userfaultfd 323
#define __NR_pidfd_getfd 438
EOF
export CICADA_SYSCALL_HEADER="${tmp}/unistd_64.h"

echo "==> generation"
bash "${GEN}" "${tmp}/f.bpf" || die "generator exited non-zero"
[[ -s "${tmp}/f.bpf" ]] || die "no program emitted"
size="$(wc -c < "${tmp}/f.bpf" | tr -d ' ')"
(( size % 8 == 0 )) || die "program is ${size} bytes, not a multiple of the 8-byte instruction"
(( size / 8 <= 4096 )) || die "program exceeds BPF_MAXINSNS"
say "emitted $(( size / 8 )) instructions"

# Refuse to emit an empty filter rather than a filter that allows everything:
# a filter that resolved no syscalls would install cleanly and protect nothing.
if CICADA_SYSCALL_HEADER=/dev/null bash "${GEN}" "${tmp}/empty.bpf" 2>/dev/null; then
  die "generator emitted a program from an empty syscall table (should refuse)"
else
  say "refuses to emit a filter that denies nothing"
fi
# Same reasoning for a header that is not there at all.
if CICADA_SYSCALL_HEADER="${tmp}/nonexistent.h" bash "${GEN}" "${tmp}/empty.bpf" 2>/dev/null; then
  die "generator succeeded with no syscall header"
else
  say "refuses to run without a syscall header"
fi

echo "==> verdicts (decoded and simulated)"
python3 - "${tmp}/f.bpf" <<'PY' || fail=1
import struct, sys

ALLOW = 0x7FFF0000
EPERM = 0x00050001
X86_64 = 0xC000003E
I386   = 0x40000003

prog = open(sys.argv[1], 'rb').read()
ins = [struct.unpack_from('<HBBI', prog, i * 8) for i in range(len(prog) // 8)]

def verdict(arch, nr):
    pc, A = 0, 0
    for _ in range(len(ins) * 2):
        code, jt, jf, k = ins[pc]
        if code == 0x20:                       # BPF_LD|BPF_W|BPF_ABS
            A = arch if k == 4 else nr
            pc += 1
        elif code == 0x15:                     # BPF_JMP|BPF_JEQ|BPF_K
            pc += 1 + (jt if A == k else jf)
        elif code == 0x35:                     # BPF_JMP|BPF_JGE|BPF_K
            pc += 1 + (jt if A >= k else jf)
        elif code == 0x06:                     # BPF_RET|BPF_K
            return k
        else:
            raise SystemExit(f"unknown opcode {code:#x} at {pc}")
    raise SystemExit("program does not terminate")

cases = [
    # (arch, nr, expected, why)
    (X86_64, 101,              EPERM, "ptrace denied"),
    (X86_64, 250,              EPERM, "keyctl denied"),
    (X86_64, 323,              EPERM, "userfaultfd denied"),
    (X86_64, 304,              EPERM, "open_by_handle_at denied"),
    (X86_64, 438,              EPERM, "pidfd_getfd denied"),
    (X86_64, 310,              EPERM, "process_vm_readv denied"),
    (X86_64, 0,                ALLOW, "read allowed"),
    (X86_64, 1,                ALLOW, "write allowed"),
    (X86_64, 60,               ALLOW, "exit allowed"),
    (X86_64, 0x40000000 | 101, EPERM, "x32 alias of a denied call still denied"),
    (X86_64, 0x40000000,       EPERM, "x32 ABI denied wholesale"),
    (I386,   101,              ALLOW, "non-native arch is not filtered with the wrong table"),
]

bad = 0
for arch, nr, want, why in cases:
    got = verdict(arch, nr)
    if got == want:
        print(f"  OK  {why}")
    else:
        print(f"  FAIL {why}: got {got:#x} want {want:#x}")
        bad = 1

# No verdict may be SECCOMP_RET_KILL_*: a denied syscall must degrade the app,
# not kill it, or a wrong entry in the deny list becomes a crash with no message.
for code, jt, jf, k in ins:
    if code == 0x06 and k not in (ALLOW, EPERM):
        print(f"  FAIL unexpected return value {k:#x} (only ALLOW and ERRNO(EPERM) are permitted)")
        bad = 1
sys.exit(bad)
PY

echo "==> the kernel's own opinion"
if [[ "$(uname -s)" == "Linux" ]] && command -v bwrap >/dev/null 2>&1; then
  mode="$(bwrap --ro-bind / / --seccomp 9 -- \
            grep -m1 '^Seccomp:' /proc/self/status 9<"${tmp}/f.bpf" 2>/dev/null | awk '{print $2}')"
  [[ "${mode}" == 2 ]] && say "kernel accepted the program (filter mode active under bwrap)" \
    || die "bwrap did not reach seccomp filter mode (got '${mode:-nothing}')"
else
  printf '  SKIP no Linux kernel / bwrap here — run tests/boot-verify.sh on the machine\n'
fi

echo
[[ "${fail}" -eq 0 ]] && echo "seccomp: all checks passed" || { echo "seccomp: FAILURES"; exit 1; }
