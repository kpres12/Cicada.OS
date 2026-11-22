#!/usr/bin/env bash
# Explain WHY two ISO builds of the same commit differ, instead of a byte offset.
#
#   repro-diff.sh <iso-a> <iso-b> <mkarchiso-work-a> <mkarchiso-work-b>
#
# Run as root inside the builder image (the work trees are root-owned and it
# has xorriso). It reports, in order:
#   1. which ISO 9660 file holds the first differing byte (cmp + report_lba)
#   2. files that differ in mkarchiso's ISO staging tree (kernel, initramfs, sfs)
#   3. whether the appended EFI system partition image differs
#   4. files/symlinks that differ inside the airootfs (what went into the sfs),
#      with a unified diff for small text files
#   5. packages whose versions differ (the usual suspect on a rolling distro)
# Never fails on a difference — it exists to describe one. Exits 2 if a tool
# it needs is missing, so a broken report can't pass for a clean one.
set -uo pipefail

iso_a="$1" iso_b="$2" wa="$3" wb="$4"
limit="${REPRO_DIFF_MAX_SHOW:-40}"

section() { printf '\n===== %s =====\n' "$*"; }

hash_tree() {
  # Relative path + sha256 for files, "-> target" for symlinks. Sorted, stable.
  # One sha256sum per batch, not per file: the airootfs has ~236k files.
  ( cd "$1" && {
      find . -type f -print0 | xargs -0 -r sha256sum | awk '{h=$1; sub(/^[0-9a-f]+  /, ""); print $0 "  " h}'
      find . -type l -printf '%p  -> %l\n'
    } | LC_ALL=C sort )
}

# Without these the sections below "pass" silently: the first run of this
# script hit a builder image with no diffutils, every diff/cmp was "command not
# found", and section 4 reported "identical file contents" off an empty file.
missing=()
for t in cmp diff xorriso sha256sum xargs; do command -v "${t}" >/dev/null 2>&1 || missing+=("${t}"); done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "repro-diff: missing required tool(s): ${missing[*]} — install them in the builder image" >&2
  exit 2
fi

section "1. first differing byte"
first="$(cmp "${iso_a}" "${iso_b}" 2>&1 | head -1)"
echo "${first:-identical}"
off="$(sed -n 's/.*differ: byte \([0-9]*\).*/\1/p' <<<"${first}")"
if [[ -n "${off}" ]]; then
  lba=$(( (off - 1) / 2048 ))
  echo "LBA ${lba}; owning file (blank = system area / boot image / appended partition):"
  xorriso -indev "${iso_a}" -find / -type f -exec report_lba -- 2>/dev/null \
    | awk -v lba="${lba}" '$1=="File" && $2=="data" {
        # File data lba:  0 ,   <start> ,   <blocks> , <filesize> , <path>
        gsub(/,/, " "); start=$5; blocks=$6
        if (lba >= start && lba < start + blocks) { $1=$2=$3=$4=$5=$6=$7=""; sub(/^ +/, ""); print "  " $0 }
      }'
fi

find_one() { find "$1" -maxdepth 3 -type d -name "$2" -print -quit; }
iso_ta="$(find_one "${wa}" iso)"; iso_tb="$(find_one "${wb}" iso)"
root_a="$(find_one "${wa}" airootfs)"; root_b="$(find_one "${wb}" airootfs)"

section "2. ISO staging tree (${iso_ta} vs ${iso_tb})"
if [[ -d "${iso_ta}" && -d "${iso_tb}" ]]; then
  diff <(hash_tree "${iso_ta}") <(hash_tree "${iso_tb}") && echo "identical"
else
  echo "staging trees not found"
fi

section "3. EFI system partition image"
efi_a="$(find "${wa}" -maxdepth 2 -name 'efiboot.img' -print -quit)"
efi_b="$(find "${wb}" -maxdepth 2 -name 'efiboot.img' -print -quit)"
if [[ -f "${efi_a}" && -f "${efi_b}" ]]; then
  cmp "${efi_a}" "${efi_b}" && echo "identical"
else
  echo "efiboot.img not found"
fi

section "4. airootfs contents (${root_a} vs ${root_b})"
if [[ -d "${root_a}" && -d "${root_b}" ]]; then
  diff <(hash_tree "${root_a}") <(hash_tree "${root_b}") > /tmp/repro-airootfs.diff
  rc=$?
  if [[ ${rc} -gt 1 ]]; then
    echo "diff failed (exit ${rc}); cannot compare airootfs trees"
  elif [[ ${rc} -eq 0 ]]; then
    echo "identical file contents (any sfs difference is metadata: modes, owners, xattrs, ordering)"
    diff <(cd "${root_a}" && find . -printf '%M %U:%G %p\n' | sort) \
         <(cd "${root_b}" && find . -printf '%M %U:%G %p\n' | sort) | head -n "${limit}"
  else
    changed="$(grep -E '^[<>] ' /tmp/repro-airootfs.diff | sed -E 's/^[<>] (.*)  [^ ]+$/\1/; s/^[<>] (.*)  -> .*$/\1/' | sort -u)"
    echo "$(wc -l <<<"${changed}") path(s) differ:"
    head -n "${limit}" <<<"${changed}" | sed 's/^/  /'
    shown=0
    while IFS= read -r p; do
      [[ ${shown} -lt 10 ]] || break
      fa="${root_a}/${p#./}" fb="${root_b}/${p#./}"
      if [[ -f "${fa}" && -f "${fb}" && $(stat -c %s "${fa}") -lt 65536 ]] && grep -Iq . "${fa}"; then
        echo "--- ${p}"
        diff -u "${fa}" "${fb}" | head -40
        shown=$((shown + 1))
      fi
    done <<<"${changed}"
  fi
else
  echo "airootfs trees not found"
fi

section "5. package versions"
pl_a="$(find "${iso_ta}" -name 'pkglist.*.txt' -print -quit 2>/dev/null)"
pl_b="$(find "${iso_tb}" -name 'pkglist.*.txt' -print -quit 2>/dev/null)"
if [[ -f "${pl_a}" && -f "${pl_b}" ]]; then
  diff "${pl_a}" "${pl_b}" && echo "identical package set"
else
  echo "pkglist not found"
fi
exit 0
