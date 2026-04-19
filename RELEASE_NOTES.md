# ⚙️ Mac PowerToys v2.1.0

A collection of powerful utilities for macOS, accessible from your menu bar. 21 feature modules and counting.

## ✨ What's New in v2.1.0

### New Modules
- **GitHub Notifier** — Monitor GitHub repos and organizations for events (push, pull request, issues, stars, forks, releases) and receive native macOS notifications. Supports GitHub OAuth device-flow authentication for private repos.
- **Image Optimizer** — Batch-compress and convert images to JPEG, PNG, or WebP with optional pixel/percent resize. Drag-and-drop input, per-file size savings, and direct Finder reveal.
- **Screen Capture** — Press ⌃⌥4 to select a screen region and copy it directly to the clipboard — no file saved to desktop.

### Improvements
- **Speech-to-Text**: Transcription tasks are now cancellable; switching files mid-transcription cancels the previous task cleanly.
- **Markdown Preview**: PDF export upgraded to native async/await for more reliable generation.
- App initialization refactored to eliminate side-effects (permission prompts, background timers) during non-app contexts.

### Bug Fixes
- Screen Ruler no longer disables itself on transient capture failures
- ZoomIt properly releases Escape key when disabled
- Webhook Notifier correctly buffers streaming data
- Clipboard Manager releases global hotkey on termination
- Screen Annotation captures all connected displays

## 📋 Requirements

- **macOS 15.5 or later**
- Apple Silicon or Intel Mac
- FFmpeg (optional, for Video Converter — installable via Homebrew from within the app)

## 🚀 Installation

1. Download `MacPowerToys-v2.0.0.dmg` from the assets below
2. Open the DMG file
3. Drag `MacPowerToys.app` to your Applications folder
4. Launch from Applications or Spotlight

## 🎯 Usage

1. Click the wrench icon in your menu bar
2. Select a tool from the feature grid
3. Each module has its own settings and controls

## 🐛 Known Issues

None at this time.

## 🔗 Links

- [Source Code](https://github.com/rbinar/mac-powertoys)
- [Report Issues](https://github.com/rbinar/mac-powertoys/issues)