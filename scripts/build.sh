#!/usr/bin/env bash
# Build Todd Wallace's source as an OS-9 module without modifying it.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
assembler="${LWASM_BIN:-lwasm}"
mkdir -p build
if ! command -v "$assembler" >/dev/null 2>&1; then
  echo "Missing LWASM: $assembler (set LWASM_BIN if installed elsewhere)" >&2
  exit 1
fi
"$assembler" --6309 --format=os9 --list=build/cctplay.lst --symbols -o build/cctplay cct_os9.asm
echo "Built $root/build/cctplay"
tool="${TOOLSHED_OS9:-/Users/magneto-optimus/Documents/Coding/toolshed-2.2/build/unix/os9}"
if [ -x "$tool" ] || command -v "$tool" >/dev/null 2>&1; then
  "$tool" ident build/cctplay
else
  echo "ToolShed os9 not found; module ident verification skipped."
fi
