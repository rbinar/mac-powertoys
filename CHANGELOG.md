# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · [SemVer](https://semver.org/)

## [Unreleased]

### Added
- Speech-to-Text module powered by WhisperKit for on-device audio transcription with model selection and real-time status. 2026-02-28 23:50
- Unit tests for Speech-to-Text model status logic. 2026-02-28 23:50
- Pomodoro Timer module with customizable focus/break sessions, auto-transitions, session tracking, and visual countdown ring. 2026-02-28 18:30
- Test Data Generator utility for generating sample test data on demand. 2026-02-28 18:30
- Video Converter module: FFmpeg-powered conversion between 16 formats (MP4, MOV, MKV, WEBM, AVI, MP3, AAC, WAV, FLAC, GIF, etc.) with quality presets, resolution options, and real-time progress. 2026-02-28 14:00
- Drag & drop file input and one-click FFmpeg installation via Homebrew in Video Converter. 2026-02-28 14:00
- Conversion history with "Show in Finder" for recent outputs in Video Converter. 2026-02-28 14:00
- Scrollable content areas in Color Picker, Crosshairs, Find My Mouse, Mouse Highlighter, Screen Annotation, Screen Ruler, and main hub views. 2026-02-28 14:00
- PR code review fixes documentation under `docs/pr-review-fixes.md`. 2026-02-27 12:00

### Changed
- Feature hub grid updated: Speech-to-Text card replaces empty slot next to Test Data Generator. 2026-02-28 23:50
- Feature hub grid reorganized into six 2-column rows with Pomodoro Timer and Test Data Generator cards. 2026-02-28 18:30
- Video Converter card changed from full-width to compact 2-column card. 2026-02-28 18:30
- "Annotation" label renamed to "Screen Annotation" in the feature hub. 2026-02-28 18:30
- ZoomIt and Screen Annotation settings collapse when the feature is disabled, showing only the enable toggle. 2026-02-28 18:30
- Added bottom spacers to Awake, Markdown Preview, Mouse Jiggler, Cursor Wrap, and Mouse Utilities hub views for consistent layout. 2026-02-28 18:30
- Improved error logging across Webhook Notifier, Clipboard Manager, and Markdown Preview with proper do-catch blocks. 2026-02-27 12:00
- Replaced `DispatchQueue.main.asyncAfter` with structured `Task.sleep` in Clipboard Manager. 2026-02-27 12:00
- Clipboard Manager icon updated from `doc.on.clipboard` to `list.clipboard`. 2026-02-28 14:00
- Menu bar popover now has a fixed height (340×560) for consistent layout. 2026-02-28 14:00
- Accessibility permission prompt only appears if not already granted, avoiding repeated dialogs. 2026-02-28 14:00
- App Sandbox disabled to support FFmpeg execution via NSUserUnixTask. 2026-02-28 14:00
- Bundle version bumped to 2. 2026-02-28 14:00

### Deprecated

### Removed
- Removed unused `Combine` import from Markdown Preview and Webhook Notifier models. 2026-02-28 23:50
- Removed unused `CoreGraphics` import from Mouse Jiggler model. 2026-02-28 23:50
- Removed dead `convertPixels` method from Screen Ruler model. 2026-02-28 23:50
- Removed stale `add_files.rb` helper script and typo entitlements file. 2026-02-28 23:50
- Moved internal troubleshooting docs from `docs/` to `.docs/` (hidden from repo root). 2026-02-28 23:50

### Fixed
- Fixed Webhook Notifier to properly buffer streaming data and handle partial messages. 2026-02-27 12:00
- Fixed Clipboard Manager global hotkey not being released on app termination. 2026-02-27 12:00
- Fixed Markdown Preview crash on files with uncommon extensions due to force-unwrapped UTType. 2026-02-27 12:00
- Fixed Markdown Preview unreliable rendering by replacing timer delay with WKNavigationDelegate. 2026-02-27 12:00
- Fixed Markdown Preview toolbar delegate singleton causing potential ownership issues. 2026-02-27 12:00
- Fixed Screen Annotation event handlers firing twice due to duplicate local and global monitors. 2026-02-27 12:00
- Fixed Screen Annotation screenshot now captures all connected displays instead of only the primary. 2026-02-27 12:00

### Security
- Added DOMPurify sanitization to Markdown Preview to prevent XSS in rendered HTML. 2026-02-27 12:00
- Fixed path traversal vulnerability in Clipboard Manager image file handling. 2026-02-27 12:00
- Removed sensitive topic identifiers from Webhook Notifier console logs. 2026-02-27 12:00

> Older releases archived in [CHANGELOG-2.md](CHANGELOG-2.md).
- 64-bit Intel or Apple Silicon Mac