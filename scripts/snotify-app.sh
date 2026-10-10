#!/usr/bin/env bash
# snotify-app.sh - build, package and install Snotify.app, the notifier bin/snotify uses.
#
# Usage: scripts/snotify-app.sh { build DIR [VERSION] | tarball DIR [VERSION] | status
#                                | install | test [--scheduled] | uninstall }
#        (or: just build | tarball | status | install | test | uninstall)
#   build DIR  build Snotify.app into DIR, signed, with bin/ and skills/ inside
#              it under Contents/Resources, so the bundle alone is a complete
#              install. VERSION goes into Info.plist; the default is the
#              nearest git tag, or 0.0.0 outside a checkout.
#   tarball DIR  write DIR/snotify-VERSION.tar.gz, the tracked tree at HEAD
#              under snotify-VERSION/, and DIR/checksums.txt beside it. What
#              the release workflow publishes and the Homebrew formula builds
#              from on the user's machine.
#   status     exit 0 when ~/Applications/Snotify.app is installed, signed, and
#              built from the sources in Sources/ as they are now
#   install    build it, sign it, install it, link ~/.local/bin/snotify and
#              snotify-claude and ~/.claude/skills/notify, and
#              post a first notification (macOS asks for permission on that one)
#   test       post a notification whose click writes a file, and say whether
#              the click arrived within 30 s. --scheduled posts it from a
#              one-off LaunchAgent instead of this terminal, which is how a
#              scheduled job's notification arrives.
#   uninstall  remove the app and the links
#
# Why an app at all: `osascript -e 'display notification'` is attributed to
# Script Editor, so every banner carries a Show button that opens an empty
# Script Editor window and nothing else can be hung on a click. A bundle of
# our own posts through UNUserNotificationCenter under its own name and icon,
# gets its own row in System Settings > Notifications, and is relaunched by
# macOS when a banner is clicked, which is where --on-click runs.
#
# Signing is ad hoc with a fixed identifier: the notification permission is
# remembered by signature, so an unsigned rebuild would ask again every time.
# There is no Developer ID behind it and nothing is notarized: the app is
# built on the machine it runs on, by `just install` or by the Homebrew
# formula, so no copy is ever downloaded and quarantined.
#
# Found on 2026-10-10: a bundle freshly copied into ~/Applications is not
# always known to LaunchServices yet, so a click could not relaunch it until
# `lsregister -f` had run; install does that now.
set -euo pipefail

self=${0##*/}
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
src=$root/Sources
wrapper=$root/bin/snotify
label=org.lonkar.snotify
app=$HOME/Applications/Snotify.app
app_exec=$app/Contents/MacOS/Snotify
app_stamp=$app/Contents/Resources/source.sha256
link=$HOME/.local/bin/snotify
# The Claude Code hook, linked beside it; ~/.claude/settings.json calls it by path.
claude_hook=$root/bin/snotify-claude
claude_link=$HOME/.local/bin/snotify-claude
# The /notify skill, linked as a directory so Claude Code lists it.
skill=$root/skills/notify
skill_link=$HOME/.claude/skills/notify
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/snotify
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

die() { printf '%s: error: %s\n' "$self" "$1" >&2; exit 1; }

[[ $(uname -s) == Darwin ]] || die "macOS only"
[[ -f $src/main.swift && -f $src/icon.swift ]] || die "sources missing under $src"
[[ -f $root/Resources/nerd-fonts/SymbolsNerdFontMono-Regular.ttf ]] || die "Resources/nerd-fonts is missing; run scripts/fetch-nerd-font.sh"

# Every Swift file, the vendored font index and this script: what the bundle is
# built from, so `status` notices a change to any of them.
source_hash() { cat "$src"/*.swift "$root/Resources/nerd-fonts/glyphnames.json" "$0" | shasum -a 256 | cut -d' ' -f1; }

# The app is every Swift file but icon.swift, which is the build-time tool that
# draws the icon set and has its own top-level code.
app_sources() { find "$src" -name '*.swift' ! -name icon.swift | sort; }

# The version for Info.plist: the argument, else the nearest tag without its v,
# else 0.0.0. CFBundleVersion has to be dotted digits, so a -dirty or -3-gabc
# suffix is kept in the short string only.
version_of() { # version_of [VERSION]
  local v=${1:-}
  if [[ -z $v ]]; then
    v=$(git -C "$root" describe --tags --always --dirty 2>/dev/null || true)
    [[ $v == v[0-9]* ]] || v=0.0.0
  fi
  printf '%s' "${v#v}"
}

build_app() { # build_app DIR [VERSION]  -> DIR/Snotify.app
  local dir=$1 version stage tmp
  version=$(version_of "${2:-}")
  stage=$dir/Snotify.app
  tmp=$(mktemp -d)
  command -v swiftc >/dev/null 2>&1 || die "swiftc not found; install the Xcode command line tools"
  rm -rf "$stage"
  mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
  # shellcheck disable=SC2046  # the file list is one path per line, none with spaces
  swiftc -O -swift-version 5 -framework AppKit -framework UserNotifications -framework CoreText \
    -o "$stage/Contents/MacOS/Snotify" $(app_sources)
  swiftc -O -swift-version 5 -framework AppKit -o "$tmp/icon" "$src/icon.swift"
  "$tmp/icon" "$tmp/Snotify.iconset"
  iconutil -c icns "$tmp/Snotify.iconset" -o "$stage/Contents/Resources/Snotify.icns"
  rm -rf "$tmp"
  # The command, the hook and the skill travel inside the bundle, so a formula
  # install has them: it links Contents/Resources/bin onto PATH.
  mkdir -p "$stage/Contents/Resources/bin" "$stage/Contents/Resources/skills"
  cp "$wrapper" "$claude_hook" "$stage/Contents/Resources/bin/"
  cp -R "$skill" "$stage/Contents/Resources/skills/"
  cp "$root/LICENSE" "$stage/Contents/Resources/"
  # Symbols Nerd Font Mono and its name index, for --icon; MIT, licence beside it.
  cp -R "$root/Resources/nerd-fonts" "$stage/Contents/Resources/nerd-fonts"
  cat > "$stage/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Snotify</string>
  <key>CFBundleDisplayName</key><string>Snotify</string>
  <key>CFBundleExecutable</key><string>Snotify</string>
  <key>CFBundleIconFile</key><string>Snotify</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>${version%%-*}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License, Yogesh Lonkar</string>
</dict>
</plist>
PLIST_EOF
  source_hash > "$stage/Contents/Resources/source.sha256"
  codesign --force --sign - --identifier "$label" "$stage" >/dev/null 2>&1
  codesign --verify --deep --strict "$stage" >/dev/null 2>&1 || die "the signature on $stage does not verify"
}

installed_ok() {
  [[ -x $app_exec && -f $app_stamp ]] || return 1
  [[ $(cat "$app_stamp") == "$(source_hash)" ]] || return 1
  codesign --verify "$app" >/dev/null 2>&1 || return 1
  [[ -L $link && $(readlink "$link") == "$wrapper" ]] || return 1
  [[ -L $claude_link && $(readlink "$claude_link") == "$claude_hook" ]] || return 1
  [[ -L $skill_link && $(readlink "$skill_link") == "$skill" ]]
}

case ${1:-} in
  build)
    dir=${2:?usage: $self build DIR [VERSION]}
    mkdir -p "$dir"
    build_app "$dir" "${3:-}"
    printf 'built %s/Snotify.app, version %s\n' "$dir" \
      "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dir/Snotify.app/Contents/Info.plist")"
    ;;
  tarball)
    dir=${2:?usage: $self tarball DIR [VERSION]}
    version=$(version_of "${3:-}")
    mkdir -p "$dir"
    out=$(cd "$dir" && pwd)/snotify-$version.tar.gz
    # The tracked tree only, so a build on the user's machine is a build of
    # what the tag holds and nothing a working copy had lying around.
    git -C "$root" archive --format=tar.gz --prefix="snotify-$version/" -o "$out" HEAD
    (cd "$dir" && shasum -a 256 "${out##*/}" > checksums.txt)
    printf 'wrote %s\n' "$out"
    cat "$dir/checksums.txt"
    ;;
  status)
    installed_ok
    ;;
  install)
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    build_app "$tmp"
    mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$state_dir"
    rm -rf "$app"
    cp -R "$tmp/Snotify.app" "$app"
    "$lsregister" -f "$app" >/dev/null 2>&1 || true
    ln -sfn "$wrapper" "$link"
    ln -sfn "$claude_hook" "$claude_link"
    mkdir -p "$HOME/.claude/skills"
    ln -sfn "$skill" "$skill_link"
    printf 'installed %s\nlinked %s -> %s\nlinked %s -> %s\nlinked %s -> %s\n' \
      "$app" "$link" "$wrapper" "$claude_link" "$claude_hook" "$skill_link" "$skill"
    printf 'posting a first notification; if macOS asks, allow Snotify to notify\n'
    "$wrapper" --title "Snotify is installed" --body "Scripts on this machine notify through this app now." \
      || printf 'that failed; see above, then System Settings > Notifications > Snotify\n' >&2
    ;;
  test)
    installed_ok || die "not installed or stale; run $0 install"
    mkdir -p "$state_dir"
    marker=$state_dir/click.$$
    rm -f "$marker"
    cmd="touch '$marker'"
    if [[ ${2:-} == --scheduled ]]; then
      # launchd starts the poster, so nothing from this terminal is in its
      # parent chain: the faithful rehearsal of a LaunchAgent's notification.
      probe=$label.probe
      probe_plist=$HOME/Library/LaunchAgents/$probe.plist
      {
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
        printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        printf '%s\n' '<plist version="1.0"><dict>'
        printf '  <key>Label</key><string>%s</string>\n' "$probe"
        printf '  <key>ProgramArguments</key><array>'
        printf '<string>%s</string>' "$wrapper" --title "Snotify test from launchd" \
          --body "Click me: that should write $marker" --sound Pop --group snotify-test --on-click "$cmd"
        printf '</array>\n'
        printf '%s\n' '  <key>RunAtLoad</key><true/>'
        printf '  <key>StandardOutPath</key><string>%s/probe.log</string>\n' "$state_dir"
        printf '  <key>StandardErrorPath</key><string>%s/probe.log</string>\n' "$state_dir"
        printf '%s\n' '</dict></plist>'
      } > "$probe_plist"
      launchctl bootout "gui/$(id -u)/$probe" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$probe_plist"
      sleep 2
      launchctl bootout "gui/$(id -u)/$probe" 2>/dev/null || true
      rm -f "$probe_plist"
      [[ -s $state_dir/probe.log ]] && { printf 'the poster said:\n'; cat "$state_dir/probe.log"; }
    else
      "$wrapper" --title "Snotify test" --body "Click me: that should write $marker" \
        --sound Pop --group snotify-test --on-click "$cmd"
    fi
    printf 'posted; click the banner within 30 s\n'
    for _ in $(seq 1 60); do
      [[ -f $marker ]] && break
      sleep 0.5
    done
    if [[ -f $marker ]]; then
      rm -f "$marker"
      printf 'ok: the click ran its command\n'
    else
      die "no click arrived in 30 s (nothing wrong if you did not click)"
    fi
    ;;
  uninstall)
    rm -rf "$app"
    [[ -L $link && $(readlink "$link") == "$wrapper" ]] && rm -f "$link"
    [[ -L $claude_link && $(readlink "$claude_link") == "$claude_hook" ]] && rm -f "$claude_link"
    [[ -L $skill_link && $(readlink "$skill_link") == "$skill" ]] && rm -f "$skill_link"
    printf 'removed %s; macOS keeps its row in System Settings > Notifications for a while\n' "$app"
    ;;
  *)
    sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
