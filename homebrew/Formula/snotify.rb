# The formula for Snotify, as it sits in lonkar-org/homebrew-tap under
# Formula/snotify.rb. This copy is the source: the release workflow copies it
# into the tap and homebrew/update-formula.sh rewrites the url and sha256 lines
# from the published release. Sixty-four zeros mean no release has filled them
# in yet, so `brew install` fails the checksum rather than installing something
# nobody verified. The version comes from the url, which is what `brew audit`
# wants.
#
# It builds from source on the machine it installs on. The app is compiled and
# signed ad hoc right there, so Gatekeeper never sees a download: no quarantine
# flag to clear and nothing to notarize. The cost is swiftc from the Xcode
# command line tools and a compile instead of a download.
class Snotify < Formula
  desc "Desktop notifications from scripts that stick, with a history"
  homepage "https://github.com/lonkar-org/snotify"
  url "https://github.com/lonkar-org/snotify/releases/download/v0.0.0/snotify-0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/lonkar-org/snotify.git", branch: "main"

  # The Claude Code hook reads its events and the transcript with jq.
  depends_on "jq"
  depends_on macos: :ventura

  def install
    odie "swiftc not found; `xcode-select --install` puts the command line tools on" unless which("swiftc")
    # Info.plist wants dotted digits, which a HEAD build has none of.
    v = build.head? ? "0.0.0" : version.to_s
    system "scripts/snotify-app.sh", "build", "dist", v
    prefix.install "dist/Snotify.app"
    # The command and the hook travel inside the bundle; these put them on PATH.
    bin.install_symlink prefix/"Snotify.app/Contents/Resources/bin/snotify"
    bin.install_symlink prefix/"Snotify.app/Contents/Resources/bin/snotify-claude"
  end

  def caveats
    <<~EOS
      Snotify.app is in #{opt_prefix}, built and signed on this machine, so
      there is no quarantine flag to clear. `snotify --title Hello` posts the
      first banner and macOS asks once whether Snotify may notify.

      `brew upgrade snotify` moves the app, so a login item turned on with
      `snotify config login on` points at the old copy afterwards: run it again.

      For the Claude Code hooks and the /notify skill, in Claude Code:

        /plugin marketplace add lonkar-org/snotify
        /plugin install snotify@snotify
    EOS
  end

  test do
    # `brew test` runs in a sandbox with no window server, and an AppKit app
    # is killed the moment it asks for one, so the app itself is not run here.
    # scripts/formula-test.sh runs `snotify icons` outside the sandbox. What
    # can be checked: the bundle is there and signed, the command on PATH is
    # the one inside it and its usage (printed to stderr) mentions --title.
    app = prefix/"Snotify.app"
    assert_predicate app/"Contents/MacOS/Snotify", :executable?
    system "codesign", "--verify", "--deep", "--strict", app
    assert_equal app/"Contents/Resources/bin/snotify", (bin/"snotify").realpath
    assert_match "--title", shell_output("#{bin}/snotify --help 2>&1")
  end
end
