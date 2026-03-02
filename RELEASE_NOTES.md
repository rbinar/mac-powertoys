# ⚙️ Mac PowerToys v2.0.0

A collection of powerful utilities for macOS, accessible from your menu bar. 16 feature modules and counting.

## ✨ What's New in v2.0.0

### New Modules
- **PDF Tools** — Split, merge, and extract PDF files
- **Port Manager** — Monitor active network ports with process info, filtering, and kill-process support
- **System Info** — Real-time CPU, memory, disk, and network statistics in the menu bar
- **Quick Launch** — Customizable keyboard shortcuts for fast app/file/URL launching with favicon support
- **Speech-to-Text** — On-device audio transcription powered by WhisperKit
- **Pomodoro Timer** — Focus/break sessions with auto-transitions, session tracking, and visual countdown
- **Test Data Generator** — Generate sample test data on demand
- **Video Converter** — FFmpeg-powered conversion between 16 formats with quality presets and progress tracking
- **Screen Annotation** — Draw on screen with screenshot capture across all displays
- **Markdown Preview** — Live preview for Markdown files with syntax highlighting
- **Clipboard Manager** — Clipboard history with global hotkey access
- **Webhook Notifier** — HTTP webhook listener with streaming support
- **Awake** — Keep your Mac awake on demand
- **Mouse Jiggler** — Simulate mouse movement to prevent sleep
- **ZoomIt** — Screen zoom and live zoom for presentations
- **Mouse Utilities** — Find My Mouse, Cursor Crosshairs, Mouse Highlighter, Cursor Wrap

### Improvements
- Scrollable content areas across all feature views
- Menu bar popover with fixed height (340×560) for consistent layout
- Accessibility permission prompt only appears when needed
- Improved error logging with proper do-catch blocks
- DOMPurify sanitization in Markdown Preview for XSS prevention

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