# snotify: Snotify.app, the `snotify` command and the Claude Code
# hook. `just` lists recipes. Each build recipe is scripts/snotify-app.sh under
# another name, so the script stays the one place the build, the signing and
# the test live, and `just ci` is what .github/workflows run.

set shell := ["bash", "-euo", "pipefail", "-c"]

scripts := justfile_directory() / "scripts"

default:
    @just --list

# Build, sign and install ~/Applications/Snotify.app; link snotify, snotify-claude, the skill
install:
    {{scripts}}/snotify-app.sh install

# Exit 0 when the installed app matches Sources/ and is signed
status:
    {{scripts}}/snotify-app.sh status

# `just test --scheduled` posts it from a one-off LaunchAgent instead.
# Post a banner whose click writes a file; say whether the click arrived
test *args:
    {{scripts}}/snotify-app.sh test {{args}}

# Exercise the Claude Code hook (bin/snotify-claude) with fake transcripts; one banner
test-claude:
    {{scripts}}/snotify-claude-test.sh

# Build DIR/Snotify.app, then exercise it: history files, search, icons, config, the window
test-app dir="dist":
    {{scripts}}/snotify-app.sh build {{dir}}
    {{scripts}}/snotify-app-test.sh {{dir}}/Snotify.app

# Fill the history with twenty demo notifications from four mocked senders, then `snotify show`
demo *args:
    {{scripts}}/snotify-demo.sh {{args}}

# Re-vendor Resources/nerd-fonts from the pinned Nerd Fonts release (`VERSION` to move it)
fetch-nerd-font version="":
    {{scripts}}/fetch-nerd-font.sh {{version}}

# just snapshot notes.md out.png
# Render the Info window for a Markdown file to a PNG, no screen capture
snapshot md out:
    "$HOME/Applications/Snotify.app/Contents/MacOS/Snotify" --show-info {{md}} --snapshot {{out}}

# Remove the app and the links
uninstall:
    {{scripts}}/snotify-app.sh uninstall

# Build DIR/Snotify.app, signed, bin/ and skills/ inside it; VERSION defaults to the nearest tag
build dir="dist" version="":
    {{scripts}}/snotify-app.sh build {{dir}} {{version}}

# Write DIR/snotify-VERSION.tar.gz and checksums.txt from HEAD, what a release publishes
tarball dir="dist" version="":
    {{scripts}}/snotify-app.sh tarball {{dir}} {{version}}

# Install the formula from a tarball of HEAD through a throwaway tap, check it, uninstall
formula-test tarball="":
    {{scripts}}/formula-test.sh {{tarball}}

# brew style on the formula
formula-lint:
    brew style homebrew/Formula/snotify.rb

# shellcheck over every script, the way the shellcheck job does
lint:
    shellcheck -S style bin/snotify bin/snotify-claude scripts/*.sh homebrew/*.sh

# markdownlint over every Markdown file, the version markdown.yml pins
lint-md:
    npx --yes markdownlint-cli2@0.23.0

# Claude Code's validator over .claude-plugin/, hooks/ and skills/, warnings as errors
plugin-validate:
    claude plugin validate --strict .

# Fail on any review marker (a question for the owner) still in the tree
review-marks:
    {{scripts}}/check-review-marks.sh

# Everything CI runs that needs no build, native; `just test-app` is the macOS build job
ci: review-marks lint lint-md formula-lint plugin-validate test-claude
    @echo "review marks, shellcheck, markdownlint, brew style, the plugin validator and the hook tests all passed"

# One version's CHANGELOG.md section; `--details 0.1.0` is what the release notes print
changelog-section *args:
    {{scripts}}/changelog-section.sh {{args}}

# Date the changelog, set the version, commit, tag vVERSION and push; `--no-push`, `--dry-run`
release version *args:
    {{scripts}}/release.sh {{version}} {{args}}
