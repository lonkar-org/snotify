#!/usr/bin/env bash
# fetch-nerd-font.sh - vendor the Nerd Fonts symbols font and glyph index into
# Resources/nerd-fonts, pinned to one release and checked against its sha256.
#
# Usage: scripts/fetch-nerd-font.sh [VERSION]   (default: the pinned one below)
#
# The app bundles Symbols Nerd Font Mono so a sender can pick a glyph by its
# Nerd Fonts name (`--icon fa-rocket`) and the banner, the history and the menu
# bar show it. glyphnames.json is the upstream name index, reduced here to
# {name: codepoint} so 10,996 names cost about 250 KB instead of 545 KB. The
# font is MIT licensed by Ryan L McIntyre; LICENSE travels beside it, into the
# bundle too.
#
# Why vendored rather than fetched at build time: a release build on a runner
# and `just install` on a laptop have to produce the same bundle, and a build
# must not depend on GitHub being up. Rerun this to move to a newer release,
# update the two checksums from what it prints, and commit the result.
set -euo pipefail

version=${1:-v3.5.1}
# sha256 of NerdFontsSymbolsOnly.tar.xz and glyphnames.json at the pinned
# version, taken on 2026-10-10. A different version prints its own and stops
# short of checking.
pinned=v3.5.1
archive_sha=01172f37db8543edb102e5cb5c64101c9f4686630804d49b419aa07b23a69996
index_sha=d2fa6615a38eb527462cb71ff17aa44b1d6453d437ed263ab8d5b458393669e8

here=$(cd -- "$(dirname -- "$0")" && pwd)
out=$here/../Resources/nerd-fonts
tmp=$(mktemp -d)
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

curl -fsSL -o "$tmp/symbols.tar.xz" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/$version/NerdFontsSymbolsOnly.tar.xz"
curl -fsSL -o "$tmp/glyphnames.json" \
  "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/$version/glyphnames.json"
got_archive=$(shasum -a 256 "$tmp/symbols.tar.xz" | cut -d' ' -f1)
got_index=$(shasum -a 256 "$tmp/glyphnames.json" | cut -d' ' -f1)
if [[ $version == "$pinned" ]]; then
  [[ $got_archive == "$archive_sha" ]] || { echo "archive sha256 mismatch: $got_archive" >&2; exit 1; }
  [[ $got_index == "$index_sha" ]] || { echo "glyphnames.json sha256 mismatch: $got_index" >&2; exit 1; }
else
  printf '%s: new version, pin these in the script:\n  archive_sha=%s\n  index_sha=%s\n' "$version" "$got_archive" "$got_index" >&2
fi
tar -xJf "$tmp/symbols.tar.xz" -C "$tmp" SymbolsNerdFontMono-Regular.ttf LICENSE
mkdir -p "$out"
cp "$tmp/SymbolsNerdFontMono-Regular.ttf" "$tmp/LICENSE" "$out/"
# {name: {char, code}} to {name: code}; METADATA kept under its own key.
python3 -I - "$tmp/glyphnames.json" "$out/glyphnames.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
out = {"METADATA": src.get("METADATA", {})}
for name, v in src.items():
    if name == "METADATA":
        continue
    out[name] = v["code"]
json.dump(out, open(sys.argv[2], "w"), separators=(",", ":"), sort_keys=True)
PY
ls -la "$out"
echo "fetch-nerd-font.sh: $version in $out"
