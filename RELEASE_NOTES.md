# ⚙️ Mac PowerToys v2.3.0

A collection of utilities for macOS, accessible from your menu bar.

## ✨ What's New in v2.3.0

### New
- **Advanced Paste** (`⌃⌥⇧V`): paste clipboard text as plain text, Markdown, pretty or minified JSON, UPPERCASE, lowercase or Title Case.
- **PowerRename**: rename many files at once with a live preview, conflict checks and undo.
- **Archive**: extract ZIP, 7z and RAR archives; create ZIP and 7z archives, optionally with a password.
- **Download Manager**: download https links over parallel connections with pause, resume and cancel; optional video downloads with yt-dlp.
- **Text Extractor** (`⌃⌥T`): drag over any area of the screen to copy its text.
- **File Locksmith**: see which processes are using a file or folder and quit them.

### Improvements
- **Clipboard history** (`⌃⌥V`) opens as a wide palette with search and preview; `Return` pastes into the app you were using.
- `Esc` goes back on tool screens.

## 📋 Requirements

- **macOS 15.5 or later**
- Apple Silicon or Intel Mac
- FFmpeg (optional, for Video Converter; installable via Homebrew from within the app)
- `sevenzip` and `unar` (optional, for Archive: `brew install sevenzip unar`)
- `yt-dlp` (optional, for video downloads: `brew install yt-dlp`)

## 🚀 Installation

**Homebrew**
```bash
brew tap rbinar/tap
brew trust rbinar/tap   # newer Homebrew versions require trusting third-party taps
brew install --cask mac-powertoys
```

**DMG**
1. Download `MacPowerToys-v2.3.0.dmg` from the assets below
2. Open the DMG and drag `MacPowerToys.app` to your Applications folder
3. Launch it; a wrench-and-screwdriver icon appears in your menu bar

> **First launch:** this build is signed but not yet notarized by Apple, so macOS blocks it the first time. Try to open the app, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

## 🔗 Links

- [Source Code](https://github.com/rbinar/mac-powertoys)
- [Report Issues](https://github.com/rbinar/mac-powertoys/issues)
