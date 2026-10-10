# The cask for Snotify.app, as it sits in lonkar-org/homebrew-tap under
# Casks/snotify.rb. This copy is the source: the release workflow copies it into
# the tap and homebrew/update-cask.sh fills the version and sha256 lines in from
# the published release. Sixty-four zeros mean no release has filled them yet,
# so `brew install` fails the checksum rather than installing something nobody
# verified.
cask "snotify" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/lonkar-org/snotify/releases/download/v#{version}/Snotify-#{version}.dmg"
  name "Snotify"
  desc "Desktop notifications from scripts that stick, with a history"
  homepage "https://github.com/lonkar-org/snotify"

  # The Claude Code hook reads its events and the transcript with jq.
  depends_on formula: "jq"
  depends_on macos: :ventura

  app "Snotify.app"
  # The command and the hook travel inside the bundle; these put them on PATH.
  binary "#{appdir}/Snotify.app/Contents/Resources/bin/snotify"
  binary "#{appdir}/Snotify.app/Contents/Resources/bin/snotify-claude"

  uninstall quit: "org.lonkar.snotify"

  zap trash: [
    "~/.local/state/snotify",
    "~/Library/Preferences/org.lonkar.snotify.plist",
  ]

  caveats do
    <<~EOS
      Snotify.app is signed ad hoc and not notarized, so macOS blocks the
      first launch of a downloaded copy. Either install with
      --no-quarantine or clear the flag once:

        xattr -dr com.apple.quarantine "#{appdir}/Snotify.app"

      Then `snotify --title Hello` posts the first banner, and macOS asks
      once whether Snotify may notify.

      For the Claude Code hooks and the /notify skill, in Claude Code:

        /plugin marketplace add lonkar-org/snotify
        /plugin install snotify@snotify
    EOS
  end
end
