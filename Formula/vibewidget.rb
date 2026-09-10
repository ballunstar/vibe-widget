class Vibewidget < Formula
  desc "Menu bar app and widget showing how much Claude and Codex usage is left"
  homepage "https://github.com/ballunstar/vibe-widget"
  url "https://github.com/ballunstar/vibe-widget/releases/download/v1.0.1/vibe-widget-1.0.1.tar.gz"
  sha256 "a1eacd10becaa5b3a2bd44bee48f03e593e7c17009858c53d635e9745c42c57e"
  license "MIT"
  head "https://github.com/ballunstar/vibe-widget.git", branch: "main"

  # Built from source, and not a cask, because macOS ties an App Group to the
  # Team ID of whoever signed the bundle: the app and its widget can only share
  # a container if you sign them yourself. A free Apple ID issues the
  # certificate that takes — no paid membership is involved.
  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma

  def install
    # Ad-hoc only. Homebrew forks its builds with setsid(2), which leaves the
    # user's security session — and the login keychain — behind, so codesign
    # has no identity here. vibewidget-refresh signs for real afterwards.
    ENV["VIBEWIDGET_VERSION"] = version.to_s
    ENV["VIBEWIDGET_BUILD"] = Time.now.to_i.to_s
    system "./build.sh", "--build-only", "--unsigned", "--no-icon"

    prefix.install "build/Build/Products/Release/VibeWidget.app"
    bin.install "Tools/refresh.sh" => "vibewidget-refresh"
    # refresh.sh fills the Team ID into these before it signs.
    (prefix/"App").install "App/VibeWidget.entitlements"
    (prefix/"Widget").install "Widget/VibeWidgetExtension.entitlements"
  end

  def caveats
    <<~EOS
      One more step — and the same one after every upgrade:

        vibewidget-refresh

      It signs the app with your own Apple Development certificate, copies it to
      ~/Applications, re-registers the widget with macOS, and launches it. Until
      it runs, the installed bundle is ad-hoc signed and macOS will not load the
      widget. No certificate yet? A free Apple ID is enough:

        Xcode > Settings… > Accounts > Manage Certificates… > + > Apple Development

      Then right-click the desktop > Edit Widgets, search for "AI Usage", and
      drag one out. The widget only reads a file the app writes, so it goes
      stale while the app is not running — add VibeWidget under System Settings
      > General > Login Items to keep it fresh.
    EOS
  end

  test do
    app = prefix/"VibeWidget.app"
    assert_predicate app/"Contents/MacOS/VibeWidget", :executable?
    assert_predicate app/"Contents/PlugIns/VibeWidgetExtension.appex", :directory?

    # The version the build stamped is what Homebrew thinks it installed.
    stamped = shell_output("/usr/bin/plutil -extract CFBundleShortVersionString raw -o - " \
                           "#{app}/Contents/Info.plist").strip
    assert_equal version.to_s, stamped

    # The entitlement templates must still carry the placeholder, or
    # vibewidget-refresh has nothing to substitute a Team ID into.
    assert_match "$(APP_GROUP_IDENTIFIER)", (prefix/"Widget/VibeWidgetExtension.entitlements").read
  end
end
