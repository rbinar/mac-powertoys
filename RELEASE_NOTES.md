# ⚙️ Mac PowerToys v2.2.0

A collection of utilities for macOS, accessible from your menu bar.

## ✨ What's New in v2.2.0

### New
- **Command palette**: press `⌃⌥Space` to search tools, modes, installed apps and your own shortcuts.
- **Launch at Login** toggle in the hub.
- **Settings persistence**: tool settings are kept between launches.
- **New app icon** and a refreshed interface: system font, consistent module headers (the whole "‹ Title" is the back button, `⌘[` also goes back), Reduce Motion support and accessibility improvements.

### Improvements
- **Screen Ruler** shows real device pixels on Retina displays and can show inches, centimeters or millimeters.
- Light mode colors are fixed.

### Bug Fixes
- Global shortcuts no longer stay inactive until the menu bar popover is opened.
- Overlays appear on the correct display on multi-monitor setups.
- **Screen Annotation**: drawings stay on the display they were drawn on.
- **Screen Capture**: `Esc` cancels the selection.
- **Command palette** opens on the screen under the cursor.
- Many smaller behavior and stability fixes.

### Removed
- **Webhook Notifier**: it depended on a third-party or self-hosted relay server.

## 📋 Requirements

- **macOS 15.5 or later**
- Apple Silicon or Intel Mac
- FFmpeg (optional, for Video Converter; installable via Homebrew from within the app)

## 🚀 Installation

**Homebrew**
```bash
brew tap rbinar/tap
brew trust rbinar/tap   # newer Homebrew versions require trusting third-party taps
brew install --cask mac-powertoys
```

**DMG**
1. Download `MacPowerToys-v2.2.0.dmg` from the assets below
2. Open the DMG and drag `MacPowerToys.app` to your Applications folder
3. Launch it; a wrench-and-screwdriver icon appears in your menu bar

> **First launch:** this build is signed but not yet notarized by Apple, so macOS blocks it the first time. Try to open the app, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

## 🔗 Links

- [Source Code](https://github.com/rbinar/mac-powertoys)
- [Report Issues](https://github.com/rbinar/mac-powertoys/issues)
