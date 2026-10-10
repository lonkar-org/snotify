#!/usr/bin/env bash
# Point a copy of the Notify cask at a published release.
#
# usage: homebrew/update-cask.sh <tag> <checksums.txt> <cask.rb>
#          <tag>            the release tag, for example v0.1.0
#          <checksums.txt>  the file published with that release, one line
#                           `<sha256>  Notify-<version>.dmg`
#          <cask.rb>        the cask to rewrite in place
#
# Rewrites the `version` and `sha256` lines. The DMG for the tag has to be in
# checksums.txt or the script stops without writing, so a release that never
# uploaded its image cannot leave a cask with a real version over a zero sum.
#
# The release workflow runs this against lonkar-org/homebrew-tap's copy after
# the publish job. By hand, when a release predates the automation:
#
#   gh release download v0.1.0 --repo lonkar-org/notification-companion --pattern checksums.txt
#   homebrew/update-cask.sh v0.1.0 checksums.txt /path/to/homebrew-tap/Casks/notify.rb
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -eq 3 ]] || usage
tag=$1 sums=$2 cask=$3
version=${tag#v}
asset=Notify-$version.dmg

[[ -f $sums ]] || { echo "no checksums file at $sums" >&2; exit 1; }
[[ -f $cask ]] || { echo "no cask at $cask" >&2; exit 1; }

# shasum writes "<sum>  <file>", sha256sum the same; split on whitespace.
sha=$(awk -v f="$asset" '{ sub(/^\*/, "", $2) } $2 == f { print $1 }' "$sums" | head -1)
[[ ${#sha} -eq 64 ]] || { echo "$asset is not listed in $sums" >&2; exit 1; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
awk -v v="$version" -v s="$sha" '
  /^[ \t]*version "/ { sub(/version "[^"]*"/, "version \"" v "\""); versions++ }
  /^[ \t]*sha256 "/  { sub(/sha256 "[^"]*"/, "sha256 \"" s "\""); sums++ }
  { print }
  END {
    if (versions != 1 || sums != 1) {
      print "update-cask.sh: rewrote " versions " version and " sums " sha256 lines, wanted one each" > "/dev/stderr"
      exit 1
    }
  }
' "$cask" > "$tmp"
# Copied rather than moved: mktemp makes the file 0600, and `brew style` fails
# a cask with those permissions.
cat "$tmp" > "$cask"
echo "update-cask.sh: $cask now points at $tag"
