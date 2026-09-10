class Vibewidget < Formula
  desc "Menu bar app and widget showing how much Claude and Codex usage is left"
  homepage "https://github.com/ballunstar/vibe-widget"
  url "https://github.com/ballunstar/vibe-widget/releases/download/v1.1.2/vibewidget-1.1.2-macos.zip"
  version "1.1.2"
  sha256 "515dc5fb1ec73e7ce8487f5c1c025bcf4ccaf9edec271c7210b06b2fc13441a0"
  license "MIT"

  # A built, signed bundle rather than a source build: macOS ties an App Group
  # to the Team ID that signed it, so the widget can only reach the app's data
  # if both carry a real signature. Signing needs a login keychain, which a
  # Homebrew build never has — it forks through setsid(2) — so the release is
  # signed on the maintainer's Mac and shipped as it is. Nothing here compiles,
  # so no Xcode and no Apple ID are required to install it.
  depends_on macos: :sonoma

  def install
    prefix.install "VibeWidget.app"
    # Homebrew may not write to $HOME, and macOS serves widgets out of a
    # LaunchServices record, so placing and registering the app is a separate
    # command the user runs.
    bin.install "Tools/refresh.sh" => "vibewidget-refresh"
    # Only `vibewidget-refresh --sign` reads these, to rebuild the entitlements
    # around a different Team ID.
    (prefix/"App").install "App/VibeWidget.entitlements"
    (prefix/"Widget").install "Widget/VibeWidgetExtension.entitlements"
  end

  def caveats
    <<~EOS
      One more step — and the same one after every upgrade:

        vibewidget-refresh

      It copies VibeWidget.app to ~/Applications, tells macOS about the widget,
      and launches the app. Then right-click the desktop > Edit Widgets, search
      for "AI Usage", and drag one out.

      The widget only reads a file the app writes, so it goes stale while the
      app is not running — turn on "Open VibeWidget at login" in Settings.

      If the widget never appears in the gallery, this Mac would not honour the
      signature it shipped with. With Xcode and a free Apple ID you can re-sign
      it as yourself:

        vibewidget-refresh --sign
    EOS
  end

  test do
    app = prefix/"VibeWidget.app"
    assert_predicate app/"Contents/PlugIns/VibeWidgetExtension.appex", :directory?

    # Shipped as a binary, so the two things a source build guaranteed now have
    # to be checked: that it runs on both architectures, and that macOS will
    # load the widget at all.
    assert_match "x86_64", shell_output("/usr/bin/lipo -archs #{app}/Contents/MacOS/VibeWidget")
    assert_match(/^TeamIdentifier=[A-Z0-9]+$/, shell_output("/usr/bin/codesign -dv #{app} 2>&1"))

    stamped = shell_output("/usr/bin/plutil -extract CFBundleShortVersionString raw -o - " \
                           "#{app}/Contents/Info.plist").strip
    assert_equal version.to_s, stamped
  end
end
