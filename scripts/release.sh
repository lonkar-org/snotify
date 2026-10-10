#!/usr/bin/env bash
# Cut a release: date the changelog, set the version, commit, tag, push.
#
# usage: scripts/release.sh VERSION [--no-push] [--dry-run]
#          VERSION     0.2.0, no v; the tag is v0.2.0
#          --no-push   commit and tag locally, push nothing
#          --dry-run   print every step, change nothing
#
# One version covers the app, the plugin and the cask, and it lives in
# .claude-plugin/plugin.json; the release gate refuses a tag that disagrees
# with it. This script is the one place that number changes, so the two cannot
# drift. It refuses a dirty tree, a branch other than main, an empty
# `## Unreleased` section and an open review marker, which are the four ways a
# tag has gone out wrong before (in tmux-companion, where this shape came from).
#
# What release.yml then does, and the deploy key the Homebrew tap needs, is in
# that workflow's header.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PLUGIN=.claude-plugin/plugin.json
CHANGELOG=CHANGELOG.md
VERSION="" PUSH=1 DRY=0

say() { printf 'release: %s\n' "$*" >&2; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '  would run: %s\n' "$*" >&2; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case $1 in
    --no-push) PUSH=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        die "unknown argument: $1" ;;
    *)         [ -z "$VERSION" ] || die "one version, not two: $VERSION and $1"
               VERSION=$1; shift ;;
  esac
done
[ -n "$VERSION" ] || { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || die "$VERSION is not X.Y.Z"
tag=v$VERSION

[ "$(git branch --show-current)" = main ] || die "release from main, not $(git branch --show-current)"
if ! git diff --quiet || ! git diff --cached --quiet; then die "the tree is dirty; commit or stash first"; fi
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "$tag exists already"
./scripts/check-review-marks.sh --quiet

current=$(jq -r .version "$PLUGIN")
[ "$current" != "$VERSION" ] || say "$PLUGIN already says $VERSION"

# The Unreleased section has to say something, and then it becomes the
# version's section, with a fresh empty Unreleased above it.
unreleased=$(awk '/^## Unreleased/ {inside=1; next} /^## / {if (inside) exit} inside' "$CHANGELOG")
[ -n "${unreleased//[[:space:]]/}" ] || die "$CHANGELOG has nothing under ## Unreleased"
today=$(date +%Y-%m-%d)

say "cutting $tag, dated $today"
if [ "$DRY" = 1 ]; then
  say "would set $PLUGIN version $current -> $VERSION"
  say "would retitle ## Unreleased as ## $VERSION - $today in $CHANGELOG"
else
  tmp=$(mktemp)
  jq --indent 2 --arg v "$VERSION" '.version = $v' "$PLUGIN" > "$tmp" && cat "$tmp" > "$PLUGIN"
  awk -v v="$VERSION" -v d="$today" '
    /^## Unreleased/ && !done { print; print ""; print "## " v " - " d; done=1; next }
    { print }
  ' "$CHANGELOG" > "$tmp" && cat "$tmp" > "$CHANGELOG"
  rm -f "$tmp"
  ./scripts/changelog-section.sh "$VERSION" > /dev/null
fi

run git add "$PLUGIN" "$CHANGELOG"
run git commit -q -m "$VERSION" -m "Cut from CHANGELOG.md's Unreleased section by scripts/release.sh."
run git tag -a "$tag" -m "$VERSION"
if [ "$PUSH" = 1 ]; then
  run git push origin main
  run git push origin "$tag"
  say "pushed; release.yml builds the DMG and waits on the release environment"
else
  say "tagged $tag locally; push with: git push origin main $tag"
fi
