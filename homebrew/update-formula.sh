#!/usr/bin/env bash
# Point a copy of the Snotify formula at a published release.
#
# usage: homebrew/update-formula.sh <tag> <checksums.txt> <formula.rb>
#          <tag>            the release tag, for example v0.1.0
#          <checksums.txt>  the file published with that release, one line
#                           `<sha256>  snotify-<version>.tar.gz`
#          <formula.rb>     the formula to rewrite in place
#
# Rewrites the `url` and `sha256` lines. The tarball for the tag has to be in
# checksums.txt or the script stops without writing, so a release that never
# uploaded its archive cannot leave a formula with a real url over a zero sum.
#
# The release workflow runs this against lonkar-org/homebrew-tap's copy after
# the publish job. By hand, when a release predates the automation:
#
#   gh release download v0.1.0 --repo lonkar-org/snotify --pattern checksums.txt
#   homebrew/update-formula.sh v0.1.0 checksums.txt /path/to/homebrew-tap/Formula/snotify.rb
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -eq 3 ]] || usage
tag=$1 sums=$2 formula=$3
version=${tag#v}
asset=snotify-$version.tar.gz

[[ -f $sums ]] || { echo "no checksums file at $sums" >&2; exit 1; }
[[ -f $formula ]] || { echo "no formula at $formula" >&2; exit 1; }

# shasum writes "<sum>  <file>", sha256sum the same; split on whitespace.
sum=$(awk -v f="$asset" '$2 == f { print $1 }' "$sums")
[[ ${#sum} -eq 64 ]] || { echo "no sha256 for $asset in $sums" >&2; exit 1; }

url="https://github.com/lonkar-org/snotify/releases/download/$tag/$asset"
# `|` as the delimiter since the url holds slashes; the lines are the only
# `url` and `sha256` in the formula.
sed -i.bak \
  -e "s|^  url \".*\"$|  url \"$url\"|" \
  -e "s|^  sha256 \".*\"$|  sha256 \"$sum\"|" \
  "$formula"
rm -f "$formula.bak"

grep -q "^  url \"$url\"$" "$formula" || { echo "the url line was not rewritten" >&2; exit 1; }
grep -q "^  sha256 \"$sum\"$" "$formula" || { echo "the sha256 line was not rewritten" >&2; exit 1; }
printf 'formula points at %s (%s)\n' "$tag" "$sum"
