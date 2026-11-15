#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
tag=${1:-bad}-$(date +%Y%m%d-%H%M%S)
src=alsa_input.usb-Corsair_CORSAIR_HS80_MAX_WIRELESS_Gaming_Receiver_DAE69076FA46E734-00.mono-fallback
echo "Talk normally for 6 seconds starting in 3..."; sleep 3; echo "RECORDING"
timeout 6 pw-record --target "$src" --rate 48000 --channels 1 "$tag.wav" || true
nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [ p.numpy ])' \
  --command python3 -I analyze.py "$tag.wav"
python3 -I dump_props.py "$tag.json"
python3 -I diff_props.py "$(ls good-*.json | head -1)" "$tag.json"
