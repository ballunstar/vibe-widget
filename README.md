# VibeWidget

A macOS widget showing how much **Claude** and **ChatGPT** usage you have left.

Two targets, because a macOS widget cannot ship on its own:

- **VibeWidget.app** — a menu bar app (no Dock icon). It fetches the numbers and
  writes them to a shared App Group container.
- **VibeWidgetExtension.appex** — the WidgetKit widget. It only *reads* that
  file and draws it.

## Installing

```bash
brew install ballunstar/tap/vibewidget
vibewidget-refresh
```

Nothing is compiled and nothing is signed on your machine, so there is no Xcode
and no Apple ID in the way — the release ships an already-signed universal
bundle. macOS 14 or newer.

No `brew tap` step: naming the formula in full is what tells recent Homebrew you
trust it. Tapping the whole tap first is what gets refused, and `brew trust
ballunstar/tap` is the answer to that.

`vibewidget-refresh` is the second half of the install, not a formality — see
[Signing](#signing). Run it again after every `brew upgrade`.

Working from a clone instead: `./build.sh` builds and installs in one step, and
needs Xcode and a certificate of your own.

## Adding the widget

Once the app is installed and running:

1. Right-click the desktop → **Edit Widgets**, or swipe in Notification Center
   and click **Edit Widgets** at the bottom.
2. Search for **AI Usage**.
3. Drag the size you want.

| Size | Layout |
|------|--------|
| **Small** | Each provider's tightest window — the one that will stop you first |
| **Medium** | Two columns side by side, both windows per provider |
| **Large** | Providers stacked, each window labelled with its own bar |

macOS medium is a 2:1 landscape tile and large is roughly square, which is the
opposite way round from how the mockups were labelled. The layouts are mapped to
the shape each family actually gets: the side-by-side design went to medium, the
stacked one to large.

The same widget appears both on the desktop and in Notification Center — one
gallery serves both.

## The app

The menu bar item shows your tightest remaining percentage. Clicking it opens a
**menu**, not a panel:

- **Open Dashboard** (⌘D) — the full window: both providers, session and weekly,
  segmented bars and ring gauges, plus which allowance resets next.
- **Settings…** (⌘,)
- **Refresh Now**
- **Quit VibeWidget** (⌘Q)

### Settings

| Pane | What it does |
|------|--------------|
| **General** | Automatic refresh + interval, menu bar visibility and what it displays, the two widget display options, open at login |
| **Accounts** | Read-only: plan, last-refresh status, and where each number comes from |
| **Notifications** | Warn once a window drops below a threshold |
| **Appearance** | Light, Dark, or Auto — applies to both app and widgets |
| **Advanced** | Reveal the shared snapshot, force a widget reload, clear the cache |

Preferences live in the App Group's `UserDefaults`, not the app's own, so
**Use compact numbers** and **Show reset time** reach the widget too.

Signing in and out is not here — that belongs to the Claude Code and Codex CLIs.
VibeWidget only reads what they leave on disk.

Notifications fire once per window *per reset cycle*: the dedupe key includes
the window's `resets_at`, so a 15-minute refresh loop cannot repeat the same
alert until the window actually rolls over.

## Where the numbers come from

Claude also reports a **per-model weekly allowance**. It does not arrive as a
named field — it is an entry in the `limits` array with `kind: "weekly_scoped"`
and the model in `scope.model.display_name`:

```json
{ "kind": "weekly_scoped", "group": "weekly", "percent": 0,
  "scope": { "model": { "display_name": "Fable" } } }
```

The medium and large widgets give it its own row beneath the session bar rather
than a third column, so the two headline numbers keep their full size. That name
is read from the response rather than hard-coded, so if the scoped model changes
the row relabels itself with no code change. The row renders nothing when the
provider reports no scoped window, which is why ChatGPT's layout is unchanged.

|         | 5-hour window | Weekly window | Source |
|---------|---------------|---------------|--------|
| Claude  | `five_hour.utilization` | `seven_day.utilization` | `api.anthropic.com/api/oauth/usage` |
| ChatGPT | `primary.used_percent` | `secondary.used_percent` | newest `~/.codex/sessions/**/rollout-*.jsonl` |

Both report **percent used**; the UI shows `100 − used`.

**ChatGPT** needs no credentials — the Codex CLI writes a `rate_limits` snapshot into its own
session logs after every turn. Because that is a *record of the last run*, a
window whose `resets_at` has already passed is reported as 0% used rather than
replaying a stale number.

**Claude** has no local cache of the official limits, so the app calls the same
endpoint `/usage` uses. This is an internal endpoint and may change without
notice — if it does, only `ClaudeUsageProvider` needs updating.

## Three constraints that shaped the design

**1. The Claude keychain item trusts exactly one binary.** Claude Code writes
its credentials with an ACL naming a single application:

```
applications (1): /usr/bin/security
requirement: identifier "com.apple.security" and anchor apple
```

Calling `SecItemCopyMatching` from this app does not just fail — it raises a
blocking SecurityAgent dialog that a background menu bar app cannot sensibly
answer and a widget extension cannot answer at all. So `ClaudeUsageProvider`
shells out to `/usr/bin/security`, the binary the ACL already trusts. Nothing
about Claude Code's own access rules is modified.

**2. macOS only loads a widget extension that is sandboxed.** Apple's own
widgets carry `com.apple.security.app-sandbox = true`; without it the extension
never appears in the gallery. But a sandboxed widget cannot read
`~/.codex/sessions`, and cannot spawn `security`.

**3. Therefore the app refreshes and the widget only renders.** They meet at the
App Group container, the one directory both can reach:

```
~/Library/Group Containers/<TeamID>.group.com.phonpreecha.vibewidget/
    Library/Application Support/VibeWidget/snapshot.json
```

The Team ID belongs to whoever signed the build — see [Signing](#signing).

The app writes it, then calls `WidgetCenter.reloadAllTimelines()`. The widget
re-reads it every 10 minutes as a fallback. **If the app is not running, the
widget goes stale** — it shows "Open VibeWidget" when the cache is missing
entirely. To keep it fresh, turn on **Open VibeWidget at login** in Settings › General.

## Appearance

`Auto` follows System Settings › Appearance. Light and Dark override it.

The app applies this to `NSApp.appearance`, because a SwiftUI
`.preferredColorScheme` does not reach window chrome like the title bar. The
widget runs in a separate process that never sees `NSApp`, so it reads the
setting from the App Group and applies it through the environment instead.

## Naming and logos

The UI says **ChatGPT**, because that is the product the quota belongs to. The
data still comes from the **Codex CLI**, so anything pointing at a file path or
telling you which tool to run keeps the Codex name — those would be wrong
otherwise. The `Provider` enum case stays `codex` too: its raw value is
persisted in the cached snapshot and in the notification dedupe keys.

Provider logos live in `Assets/` and are built into **both** targets — a widget
extension is its own bundle and cannot reach the app's resources. They load via
`NSImage(named:)` rather than `Image("name")`, since the SwiftUI initialiser
resolves against an asset catalog and these ship as loose PNGs.

`Assets/navicon.png` is the menu bar mark, app target only. It is black on
transparent and flagged `isTemplate`, so macOS re-colours it to suit whichever
menu bar it is drawn into — one asset covers both light and dark, and a
separate white version would be redundant.

## App icon

`Tools/MakeIcon.swift` draws the icon — a split donut, coral for Claude and cyan
for Codex — and `build.sh` renders every iconset size from it. Drawing beats
exporting one PNG and downsampling: the 16pt icon is rendered at 16pt.

The same two colours are the providers' accents throughout the UI.

`App/AppIcon.icns` is committed all the same, because Homebrew puts its own
compiler shims ahead of `swiftc` and the renderer does not survive that.
`./build.sh` redraws it; `--no-icon` builds against the committed one.

## Signing

Ad-hoc signing (`-`) builds fine but the widget never registers, so the bundle
has to carry a real **Apple Development** identity. Automatic signing asks for a
*Mac Development* certificate instead, so signing is manual:

```
CODE_SIGN_STYLE    = Manual
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM   = <the certificate's OU>
```

The Team ID is the certificate's **OU**, not the identifier shown inside the
identity's name, and it is read off the certificate at build time rather than
written down. One detected value reaches all three places that need it:
`DEVELOPMENT_TEAM`, the `$(APP_GROUP_IDENTIFIER)` in both entitlement files, and
an `AppGroupIdentifier` key in both `Info.plist`s that `UsageStore` reads back.

**Who signs, and where.** Not the person installing: releases are signed on the
maintainer's Mac and shipped built, which is what keeps Xcode and an Apple ID
off the list of things an install needs. Neither CI nor Homebrew could do it
anyway — both fork their work through `setsid(2)` ([`sandbox.rb`][sandbox]),
which leaves the user's security session behind, and without a login keychain
`codesign` reports *no identity found*. Turning the Homebrew sandbox off does
not help; the fork is unconditional.

Gatekeeper rejects an Apple Development signature — `spctl` says so plainly —
but it is only consulted for quarantined files, and a Homebrew *formula* leaves
none behind. (A *cask* does, which is one reason this is not one, and why the
same bundle handed over as a `.dmg` would be blocked.)

A signature that macOS calls development still travels: the App Group only
requires that the identifier's prefix match the Team ID that *signed* the
bundle, which is a property of the signature and not of the Mac reading it. The
widget registers on a machine that has never seen the certificate — confirmed on
a second Mac, since the reasoning alone is not worth much here.

**`vibewidget-refresh` is what remains.** Homebrew may not write to `$HOME`, and
the widget gallery serves the extension from a LaunchServices record, so an
upgraded `.appex` keeps running the old code until the app is re-registered.
The command copies the bundle to `~/Applications`, re-registers it, and starts
it.

Its `--sign` flag re-signs the installed copy with your own certificate and
rewrites the group identifier to match. Nothing in the normal path needs it; it
is there for a bundle built with `--unsigned`, and as the repair if a Mac ever
does refuse the shipped signature — the widget would be missing from the gallery
while the menu bar app still worked. That path is the one that needs Xcode and a
free Apple ID.

Distributing without any of this would need a **Developer ID** certificate and
notarisation, both of which require the paid Apple Developer Program.

[sandbox]: https://github.com/Homebrew/brew/blob/main/Library/Homebrew/sandbox.rb

## Layout

```
Shared/      compiled into both targets
  UsageModels.swift          UsageWindow / ProviderUsage / UsageSnapshot
  ClaudeUsageProvider.swift  security(1) → OAuth usage endpoint
  CodexUsageProvider.swift   tail of the newest rollout log
  UsageStore.swift           refresh + App Group cache
  UsageViews.swift           UsageBar, ProviderCard
  AppSettings.swift          preferences, in the App Group suite
App/         menu bar app — owns refreshing
  VibeWidgetApp.swift        menu, window scenes, refresh timer, alerts
  DashboardView.swift        RingGauge, SegmentedBar, provider cards
  SettingsView.swift         sidebar panes, login item
Widget/      WidgetKit extension — read-only
Tools/
  MakeIcon.swift             draws AppIcon.icns, one render per iconset size
  refresh.sh                 install, re-register, optionally re-sign —
                             installed as vibewidget-refresh
  release.sh                 build, sign, publish, update the tap
Formula/vibewidget.rb        the Homebrew formula, mirrored into the tap
generate_project.py          emits VibeWidget.xcodeproj
```

`VibeWidget.xcodeproj` is generated. Change build settings in
`generate_project.py` and re-run `./build.sh`, or edits will be overwritten.

## Releasing

```bash
Tools/release.sh 1.1.0
```

It builds a universal Release, refuses to continue unless the result carries a
Team ID, packages the bundle with `ditto`, tags, publishes the release, rewrites
the `url`, `version` and `sha256` in `Formula/vibewidget.rb`, and pushes that to
`ballunstar/homebrew-tap`. Users then run `brew upgrade && vibewidget-refresh`.

This is a local script rather than a workflow because the machine with the
certificate is the only one that can produce a shippable bundle. CI still builds
every push, unsigned, to catch what a compiler can catch.

The version reaches the app through `VIBEWIDGET_VERSION`; without it
`generate_project.py` falls back to `git describe`, so a plain `./build.sh`
stamps whatever the last tag was.
