#!/bin/zsh
# Incremental native OCR runtime build. Fetches the pinned llama.cpp revision
# as build sources only — never model weights.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

src="$root/Native/OCR"
out="$root/build/ocr-runtime"
mkdir -p "$out"

cmake -S "$src" -B "$out" -DCMAKE_BUILD_TYPE=Release "$@"
cmake --build "$out" --config Release

helper="$out/OrangeOCRHelper"
if [[ -x "$helper" ]]; then
  echo "Built $helper"
  "$helper" --capabilities
else
  echo "OCR helper missing at $helper" >&2
  exit 1
fi
