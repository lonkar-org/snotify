# The cask for Notify.app, as it sits in lonkar-org/homebrew-tap under
# Casks/notify.rb. This copy is the source: the release workflow copies it into
# the tap and homebrew/update-cask.sh fills the version and sha256 lines in from
# the published release. Sixty-four zeros mean no release has filled them yet,
# so `brew install` fails the checksum rather than installing something nobody
# verified.
cask "notify" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/lonkar-org/notification-companion/releases/download/v#{version}/Notify-#{version}.dmg"
  name "Notify"
  desc "Desktop notifications from scripts, with a click action and an Info window"
  homepage "https://github.com/lonkar-org/notification-companion"

  # The Claude Code hook reads its events and the transcript with jq.
  depends_on formula: "jq"
  depends_on macos: :ventura

  app "Notify.app"
  # The command and the hook travel inside the bundle; these put them on PATH.
  binary "#{appdir}/Notify.app/Contents/Resources/bin/notify"
  binary "#{appdir}/Notify.app/Contents/Resources/bin/notify-claude"

  uninstall quit: "org.lonkar.notify"

  zap trash: [
    "~/.local/state/notify",
    "~/Library/Preferences/org.lonkar.notify.plist",
  ]

  caveats do
    <<~EOS
      Notify.app is signed ad hoc and not notarized, so macOS blocks the
      first launch of a downloaded copy. Either install with
      --no-quarantine or clear the flag once:

        xattr -dr com.apple.quarantine "#{appdir}/Notify.app"

      Then `notify --title Hello` posts the first banner, and macOS asks
      once whether Notify may notify.

      For the Claude Code hooks and the /notify skill, in Claude Code:

        /plugin marketplace add lonkar-org/notification-companion
        /plugin install notification-companion@notification-companion
    EOS
  end
end
