#!/usr/bin/env bash
# Build the cBPF program that cicada-run hands to bubblewrap's --seccomp.
#
# Why this exists at all:
#   bubblewrap does NOT install a syscall filter unless you give it one. Without
#   this, every "sandboxed" app in Cicada could still call keyctl, userfaultfd,
#   perf_event_open, process_vm_readv or open_by_handle_at against the same
#   kernel that holds the volume key. Namespaces hide resources; they do not
#   reduce the kernel surface the app can reach. Filtering the syscalls is the
#   part that reduces surface, and it is what Flatpak has shipped for years.
#
# Why hand-assembled cBPF and not libseccomp:
#   cicada-defaults is arch=any and builds nothing. Pulling in a compiler to
#   emit forty instructions would make the package architecture-specific and put
#   a binary blob in the tree that nobody can read. seccomp's program format is
#   fixed-width and trivial: 8 bytes per instruction, four fields. The whole
#   assembler is thirty lines, and every byte it emits is derived from the
#   kernel's own uapi header at generation time rather than from numbers typed
#   here — a hardcoded syscall table is how a filter silently blocks the wrong
#   call after a kernel bump.
#
# Failure policy: SECCOMP_RET_ERRNO(EPERM), never SECCOMP_RET_KILL. A denied
# syscall must look to the app like "not permitted" — the same shape as a scope
# denial — not like a crash. Denying these only reduces protection if it fails,
# so per the project rule it degrades visibly rather than killing the process.
#
# Usage:
#   cicada-seccomp-gen [OUTFILE]   write the program (default: stdout)
#   cicada-seccomp-gen --list      print the resolved syscall table, no binary
set -euo pipefail

HDR="${CICADA_SYSCALL_HEADER:-/usr/include/asm/unistd_64.h}"

# Syscalls a desktop app in a Cicada scope has no business making.
#
# Several of these are already closed by /etc/sysctl.d/99-cicada.conf
# (unprivileged_bpf_disabled, perf_event_paranoid, unprivileged_userfaultfd,
# kexec_load_disabled, dmesg_restrict, yama.ptrace_scope). They are repeated here
# because a sysctl is one `sysctl -w` away from being undone by anything running
# as root, while this filter is inherited by the process and cannot be lifted
# afterwards — not even by the app itself. The ones that are NOT redundant, and
# are the actual reason this file exists, are marked (*).
DENY=(
  # Reading or writing another process that shares this uid. Yama covers ptrace;
  # nothing covers the vm_ calls if ptrace_scope is ever relaxed.
  ptrace
  process_vm_readv           # (*)
  process_vm_writev          # (*)
  pidfd_getfd                # (*) steal an open fd out of another process

  # Kernel keyring: not used by any desktop app, and a recurring source of
  # privilege-escalation bugs.
  add_key                    # (*)
  request_key                # (*)
  keyctl                     # (*)

  # Kernel-surface syscalls with a long exploit history.
  userfaultfd                # widens use-after-free races into reliable ones
  perf_event_open
  bpf
  modify_ldt                 # (*) 16-bit segment descriptors; pure surface here

  # Filesystem handles: the classic path out of a mount namespace, because a
  # handle resolves against the superblock and ignores the sandbox's view of it.
  open_by_handle_at          # (*)
  name_to_handle_at          # (*)

  # Machine-level operations. All would need capabilities the sandbox does not
  # have, so these are documentation as much as enforcement — the filter states
  # that no scope, ever, grows into one of these.
  kexec_load
  kexec_file_load
  init_module
  finit_module
  delete_module
  iopl
  ioperm
  swapon                     # there is no swap on this OS by design
  swapoff
  acct
  quotactl
  uselib
  syslog                     # dmesg

  # NUMA policy. No laptop app needs it; each has had memory-corruption bugs.
  mbind                      # (*)
  get_mempolicy              # (*)
  set_mempolicy              # (*)
  migrate_pages              # (*)
  move_pages                 # (*)
)

# --- cBPF assembler ----------------------------------------------------------
# struct sock_filter { u16 code; u8 jt; u8 jf; u32 k; }  — native (little) endian.
BPF_LD_W_ABS=$(( 0x00 | 0x00 | 0x20 ))   # BPF_LD | BPF_W | BPF_ABS
BPF_JEQ_K=$((    0x05 | 0x10 | 0x00 ))   # BPF_JMP | BPF_JEQ | BPF_K
BPF_JGE_K=$((    0x05 | 0x30 | 0x00 ))   # BPF_JMP | BPF_JGE | BPF_K
BPF_RET_K=$((    0x06 | 0x00 ))          # BPF_RET | BPF_K

AUDIT_ARCH_X86_64=$(( 0xC000003E ))
SECCOMP_RET_ALLOW=$(( 0x7FFF0000 ))
SECCOMP_RET_ERRNO_EPERM=$(( 0x00050000 | 1 ))
X32_BIT=$(( 0x40000000 ))

# offsetof(struct seccomp_data, nr) == 0, offsetof(..., arch) == 4
OFF_NR=0
OFF_ARCH=4

byte() { printf "\\$(printf '%03o' "$(( $1 & 0xff ))")"; }

insn() { # code jt jf k
  local code="$1" jt="$2" jf="$3" k="$4"
  byte "${code}"; byte "$(( code >> 8 ))"
  byte "${jt}"; byte "${jf}"
  byte "${k}"; byte "$(( k >> 8 ))"; byte "$(( k >> 16 ))"; byte "$(( k >> 24 ))"
}

nr_of() {
  # The kernel's own table, not ours. Absent names are skipped, not guessed.
  awk -v n="__NR_$1" '$1 == "#define" && $2 == n { print $3; exit }' "${HDR}"
}

[[ -r "${HDR}" ]] || {
  echo "cicada-seccomp-gen: no syscall header at ${HDR} (install linux-api-headers)" >&2
  exit 1
}

names=()
nums=()
missing=()
for name in "${DENY[@]}"; do
  n="$(nr_of "${name}")"
  if [[ "${n}" =~ ^[0-9]+$ ]]; then
    names+=("${name}")
    nums+=("${n}")
  else
    missing+=("${name}")
  fi
done

if [[ "${1:-}" == "--list" ]]; then
  for i in "${!names[@]}"; do
    printf '%-20s %s\n' "${names[$i]}" "${nums[$i]}"
  done
  [[ "${#missing[@]}" -eq 0 ]] \
    || printf 'not in %s (skipped): %s\n' "${HDR}" "${missing[*]}" >&2
  printf 'total %d denied, %d instructions\n' "${#nums[@]}" "$(( 7 + ${#nums[@]} ))"
  exit 0
fi

N="${#nums[@]}"
[[ "${N}" -gt 0 ]] || { echo "cicada-seccomp-gen: resolved no syscalls — refusing to emit an empty filter" >&2; exit 1; }
# jt is one byte. Far more headroom than this list needs, but an unchecked
# overflow here would silently jump to the wrong instruction.
[[ "${N}" -le 250 ]] || { echo "cicada-seccomp-gen: deny list too long for 8-bit jumps" >&2; exit 1; }

# Layout:
#   0        load arch
#   1        arch == x86_64 ? -> 3 : fall through
#   2        RET ALLOW            (non-native: 32-bit multilib, see below)
#   3        load nr
#   4        nr >= 0x40000000 ? -> DENY   (x32 ABI aliases native numbers)
#   5..5+N-1 nr == denied[i] ? -> DENY
#   5+N      RET ALLOW
#   6+N      RET ERRNO(EPERM)     == DENY
DENY_IDX=$(( 6 + N ))

emit() {
  insn "${BPF_LD_W_ABS}" 0 0 "${OFF_ARCH}"
  insn "${BPF_JEQ_K}" 1 0 "${AUDIT_ARCH_X86_64}"
  # A 32-bit (i386) process arrives here. Its syscall NUMBERS ARE DIFFERENT, so
  # applying the x86_64 table to it would deny an essentially random set of
  # calls — __NR_ptrace on i386 is 26, which is __NR_geteuid on x86_64. Letting
  # it through unfiltered is the honest choice: Cicada ships no multilib apps, so
  # in practice nothing reaches this instruction, and a wrong filter is worse
  # than a documented absent one. cicada-run prints the gap if it ever fires.
  insn "${BPF_RET_K}" 0 0 "${SECCOMP_RET_ALLOW}"
  insn "${BPF_LD_W_ABS}" 0 0 "${OFF_NR}"
  # x32 shares AUDIT_ARCH_X86_64 but sets bit 30 in the syscall number, so
  # without this an x32 binary would call any denied syscall as nr|0x40000000
  # and match none of the comparisons below.
  insn "${BPF_JGE_K}" "$(( DENY_IDX - 4 - 1 ))" 0 "${X32_BIT}"
  local i idx
  for i in "${!nums[@]}"; do
    idx=$(( 5 + i ))
    insn "${BPF_JEQ_K}" "$(( DENY_IDX - idx - 1 ))" 0 "${nums[$i]}"
  done
  insn "${BPF_RET_K}" 0 0 "${SECCOMP_RET_ALLOW}"
  insn "${BPF_RET_K}" 0 0 "${SECCOMP_RET_ERRNO_EPERM}"
}

out="${1:-}"
if [[ -n "${out}" && "${out}" != "-" ]]; then
  tmp="${out}.tmp.$$"
  emit > "${tmp}"
  chmod 0444 "${tmp}"
  mv -f "${tmp}" "${out}"
else
  emit
fi
