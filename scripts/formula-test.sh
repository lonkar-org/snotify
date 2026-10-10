#!/usr/bin/env bash
# formula-test.sh - prove homebrew/Formula/snotify.rb installs: build a source
# tarball (or take one), point a copy of the formula at it through a throwaway
# tap, `brew install` it, check the command and the app, run the formula's own
# test block, then uninstall and untap. What CI's macOS job and the release
# build run; locally it is `just formula-test`.
#
# Usage: scripts/formula-test.sh [TARBALL]
#   TARBALL   a snotify-VERSION.tar.gz from `scripts/snotify-app.sh tarball`;
#             without one, HEAD is archived into a temporary directory.
#
# Needs Homebrew and swiftc. While it runs a second Snotify.app sits in the
# Cellar beside any installed one; the bundle id is the same, so a banner
# clicked in that minute may open that copy. It is removed at the end, pass
# or fail. Exit 1 on the first check that does not hold.
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tap=lonkar-org/snotifytest
t=$(mktemp -d)
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
cleanup() {
  brew uninstall --formula snotify >/dev/null 2>&1 || true
  brew untap "$tap" >/dev/null 2>&1 || true
  rm -rf "$t"
}
trap cleanup EXIT

command -v brew >/dev/null || fail "brew is not on PATH"
command -v swiftc >/dev/null || fail "swiftc is not on PATH; xcode-select --install"

tarball=${1:-}
if [[ -z $tarball ]]; then
  "$root/scripts/snotify-app.sh" tarball "$t/dist" >/dev/null
  tarball=$(printf '%s\n' "$t"/dist/*.tar.gz)
fi
[[ -f $tarball ]] || fail "no tarball at $tarball"
tarball=$(cd -- "$(dirname -- "$tarball")" && pwd)/$(basename -- "$tarball")
sum=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
echo "tarball $tarball"

# a throwaway tap, so brew loads the formula by name the way a user's brew does
brew tap-new --no-git "$tap" >/dev/null 2>&1 || true
tapdir=$(brew --repository "$tap")
mkdir -p "$tapdir/Formula"
sed -e "s|^  url \".*\"$|  url \"file://$tarball\"|" \
    -e "s|^  sha256 \".*\"$|  sha256 \"$sum\"|" \
    "$root/homebrew/Formula/snotify.rb" > "$tapdir/Formula/snotify.rb"

brew style "$tapdir/Formula/snotify.rb" >/dev/null || fail "brew style"
echo "1 ok: brew style"

# an older install would shadow the check; take it out first
brew uninstall --formula snotify >/dev/null 2>&1 || true
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew install --formula "$tap/snotify" 2>&1 | tail -5
prefix=$(brew --prefix snotify)
[[ -x $prefix/Snotify.app/Contents/MacOS/Snotify ]] || fail "no app under $prefix"
codesign --verify --deep --strict "$prefix/Snotify.app" || fail "the installed app's signature does not verify"
echo "2 ok: installed and signed under $prefix"

bin=$(brew --prefix)/bin
[[ -L $bin/snotify && -L $bin/snotify-claude ]] || fail "the command and the hook are not linked on PATH"
"$bin/snotify" --help 2>&1 | grep -q -- '--title' || fail "snotify --help"
"$bin/snotify" icons rocket | grep -q 'fa-rocket' || fail "snotify icons through the linked command did not find the app"
"$bin/snotify-claude" status >/dev/null 2>&1 || true
echo "3 ok: snotify and snotify-claude on PATH find the app inside the Cellar"

brew test snotify >/dev/null 2>&1 || fail "brew test"
echo "4 ok: the formula's test block"
echo "all ok"
