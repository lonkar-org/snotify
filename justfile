# notification-companion: Notify.app, the `notify` command and the Claude Code
# hook. `just` lists recipes. Each build recipe is scripts/notify-app.sh under
# another name, so the script stays the one place the build, the signing and
# the test live, and `just ci` is what .github/workflows run.

set shell := ["bash", "-euo", "pipefail", "-c"]

scripts := justfile_directory() / "scripts"

default:
    @just --list

# Build, sign and install ~/Applications/Notify.app; link notify, notify-claude, the skill
install:
    {{scripts}}/notify-app.sh install

# Exit 0 when the installed app matches Sources/ and is signed
status:
    {{scripts}}/notify-app.sh status

# `just test --scheduled` posts it from a one-off LaunchAgent instead.
# Post a banner whose click writes a file; say whether the click arrived
test *args:
    {{scripts}}/notify-app.sh test {{args}}

# Exercise the Claude Code hook (bin/notify-claude) with fake transcripts; one banner
test-claude:
    {{scripts}}/notify-claude-test.sh

# Build DIR/Notify.app, then exercise it: history files, search, icons, config, the window
test-app dir="dist":
    {{scripts}}/notify-app.sh build {{dir}}
    {{scripts}}/notify-app-test.sh {{dir}}/Notify.app

# Fill the history with twenty demo notifications from four mocked senders, then `notify show`
demo *args:
    {{scripts}}/notify-demo.sh {{args}}

# Re-vendor Resources/nerd-fonts from the pinned Nerd Fonts release (`VERSION` to move it)
fetch-nerd-font version="":
    {{scripts}}/fetch-nerd-font.sh {{version}}

# just snapshot notes.md out.png
# Render the Info window for a Markdown file to a PNG, no screen capture
snapshot md out:
    "$HOME/Applications/Notify.app/Contents/MacOS/Notify" --show-info {{md}} --snapshot {{out}}

# Remove the app and the links
uninstall:
    {{scripts}}/notify-app.sh uninstall

# Build DIR/Notify.app, signed, bin/ and skills/ inside it; VERSION defaults to the nearest tag
build dir="dist" version="":
    {{scripts}}/notify-app.sh build {{dir}} {{version}}

# Build, then write DIR/Notify-VERSION.dmg and checksums.txt, what a release publishes
dmg dir="dist" version="":
    {{scripts}}/notify-app.sh dmg {{dir}} {{version}}

# shellcheck over every script, the way the shellcheck job does
lint:
    shellcheck -S style bin/notify bin/notify-claude scripts/*.sh homebrew/*.sh

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
ci: review-marks lint lint-md plugin-validate test-claude
    @echo "review marks, shellcheck, markdownlint, the plugin validator and the hook tests all passed"

# One version's CHANGELOG.md section; `--details 0.1.0` is what the release notes print
changelog-section *args:
    {{scripts}}/changelog-section.sh {{args}}

# Date the changelog, set the version, commit, tag vVERSION and push; `--no-push`, `--dry-run`
release version *args:
    {{scripts}}/release.sh {{version}} {{args}}
