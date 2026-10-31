# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · [SemVer](https://semver.org/)

## [Unreleased]

### Removed
- Webhook Notifier module removed; it depended on a third-party/self-hosted ntfy relay server. 2026-11-01 00:00

## [2.1.0] - 2026-04-20

### Added
- GitHub Notifier module: monitor GitHub repos and organizations for events (push, pull request, issues, stars, forks, releases) and receive native macOS notifications. Supports GitHub OAuth device-flow authentication for private repos. 2026-04-19 00:00
- Image Optimizer module: batch-compress and convert images to JPEG, PNG, or WebP with optional pixel/percent resize. Drag-and-drop input, per-file size savings, and direct Finder reveal. 2026-04-19 00:00
- Screen Capture module: press ⌃⌥4 to select a screen region and copy it directly to the clipboard — no file saved to desktop. 2026-03-03 00:00

### Changed
- App initialization refactored into a separate `AppRootView` so all `@StateObject` models are not created during unit test runs, eliminating test-time side-effects such as permission prompts and background timers. 2026-04-19 00:00
- Hub grid: Webhook Notifier converted to a compact card matching the rest of the grid; new rows added for Image Optimizer and GitHub Notifier. 2026-04-19 00:00
- Markdown Preview: PDF export upgraded from callback-based `createPDF` to native async/await `WKWebView.pdf()`. 2026-04-19 00:00
- Speech-to-Text: transcription tasks are now cancellable; switching files mid-transcription cancels the previous task cleanly. 2026-04-19 00:00
- `release.sh` rewritten with Developer ID certificate pre-check, notarization via `notarytool`, and Gatekeeper stapling. 2026-04-19 00:00
- Entitlements updated: replaced sandbox/network-client/files entitlements with `cs.disable-library-validation` and `device.audio-input`. 2026-04-19 00:00
- `.gitignore` updated to exclude `.blink/`, `.docs/`, `.github/`, `.playwright-mcp/`, and build log files. 2026-04-19 00:00

### Removed
- `.blink/` developer documentation files removed from the repository (architecture, conventions, stack, testing). 2026-04-19 00:00
- `.docs/` internal troubleshooting docs removed from the repository. 2026-04-19 00:00
- `.github/copilot-instructions.md` removed from the repository; moved to user-level VS Code prompts. 2026-04-19 00:00

### Fixed
- Video Converter: removed duplicate debug log line that printed FFmpeg path twice on detection. 2026-04-19 00:00

## [2.0.0] - 2026-03-02

### Added
- Favicon support for URL entries in Quick Launch — website icons are fetched and displayed automatically. 2026-03-02 14:00
- Hover actions (edit/delete) and delete confirmation dialog on Quick Launch entry rows. 2026-03-02 14:00
- Input validation in Quick Launch entry form for file paths and URL format. 2026-03-02 14:00
- PDF Tools module for splitting, merging, and extracting PDF files. 2026-03-02 04:00
- Port Manager module for monitoring active network ports with process info, filtering, and kill-process support. 2026-03-01 00:00
- System Info module displaying real-time CPU, memory, disk, and network statistics in the menu bar. 2026-03-01 00:00
- Quick Launch module with customizable keyboard shortcuts for fast app/file/URL launching. 2026-03-01 00:00
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
- Quick Launch search now includes indexed applications alongside custom entries. 2026-03-02 14:00
- Quick Launch entry rows extracted into standalone `CustomEntryRow` view with app icons from NSWorkspace. 2026-03-02 14:00
- Added `.github/copilot-instructions.md` macOS Permissions and Async documentation to prevent code generation issues. 2026-03-02 04:00
- Updated main UI hub grid to position PDF Tools alongside Quick Launch. 2026-03-02 04:00
- Feature hub grid expanded with Port Manager, System Info, and Quick Launch cards in new rows. 2026-03-01 00:00
- Project documentation added under `.blink/` and `.github/copilot-instructions.md`. 2026-03-01 00:00
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
- Fixed Screen Ruler disabling itself on transient capture failures even when screen recording permission is granted. 2026-03-02 14:00
- Fixed Quick Launch failing to auto-focus search field upon activation. 2026-03-02 04:00
- Fixed Screen Ruler UI bouncing back by checking for Screen Recording permission before activating. 2026-03-02 04:00
- Fixed ZoomIt occasionally leaving the Escape key globally bound after being disabled. 2026-03-02 04:00
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

## [Unreleased] (Archived Entries)

### Added
- Screen Annotation module with freehand, line, arrow, rectangle, ellipse, and text drawing tools (`⌃⌥D`).
- Customizable default color, line width, and dim-background option for Screen Annotation.
- Undo support for annotations via `⌘Z` or right-click.
- Troubleshooting guide for Screen Recording permission in `docs/`.
- Added Markdown Preview module with live preview of `.md` files in a resizable window.
- PDF export for Markdown files directly from the preview window toolbar.
- Paste from Clipboard support to preview markdown content without opening a file.
- Light/Dark theme toggle for Markdown Preview.
- Recent files list with security-scoped bookmarks for persistent sandbox access.
- Auto-reload when the previewed markdown file changes on disk.
- Added Clipboard Manager module to track copied text and images with searchable history (`⌃⌥V`).
- Pin important clipboard items to keep them permanently.
- Adjustable history limit (10, 25, 50, or 100 items) for Clipboard Manager.
- Added Awake module to prevent Mac from sleeping with indefinite and timed modes.
- Added Keep Display On option to Awake module to prevent screen sleep.
- Added Mouse Jiggler module to simulate tiny mouse movements and prevent "Away" status in apps like Teams and Slack.
- Added adjustable interval setting (10s-120s) for Mouse Jiggler.
- Added Webhook Notifier module to receive and display real-time notifications instantly.
- Added ability to subscribe to specific topics and filter notifications in Webhook Notifier.
- Added interactive alerts for webhook notifications to take action directly.
- Added toggle to enable or disable specific webhooks as needed.
- Added ZoomIt module with Screen Zoom (⌃⌥Z) and Live Zoom (⌃⌥L) features.
- Screen Zoom allows static magnification of the screen with smooth panning.
- Live Zoom provides real-time magnification following the cursor using high-performance ScreenCaptureKit.
- Global keyboard shortcut ⌃⌥C (Control+Option+C) to launch the Color Picker screen sampler from anywhere.
- Global keyboard shortcut ⌃⌥R (Control+Option+R) to toggle Screen Ruler on/off from anywhere.
- ESC key closes the Screen Ruler overlay when active.
- Added Screen Recording permission check and alert for the Screen Ruler feature.
- Added a Mac PowerToys feature hub in the menu bar popover with quick access to modules.
- Added Mouse Utilities module with four features: Find My Mouse, Mouse Highlighter, Mouse Crosshairs, and Cursor Wrap.
- Find My Mouse dims all screens and spotlights the cursor when activated via double-tap Left Control.
- Mouse Highlighter draws colored circles on left/right clicks to highlight cursor activity.
- Mouse Crosshairs shows a full-screen crosshair overlay that follows the cursor.
- Cursor Wrap teleports the cursor to the opposite screen edge when it hits a boundary.
- Global keyboard shortcuts for all Mouse Utilities features now require Accessibility permission.

### Changed
- Screen Ruler toolbar redesigned with SF Symbols and vibrancy background for a polished look.
- Screen Ruler permission check moved to post-capture for smoother activation flow.
- Redesigned feature hub as a compact 2-column grid layout for better space utilization.
- Menu bar popover height now adjusts automatically based on content instead of a fixed max height.
- Module cards show a lighter hover effect on mouse-over for better interactivity feedback.
- Color Picker eyedropper and copy buttons are now circular instead of rounded squares.
- Mouse Utilities module icon changed from "cursorarrow.rays" to a simpler "cursorarrow".
- Renamed the app and Xcode project from MenuBarColorPicker to MacPowerToys, including targets, scheme references, and bundle identifiers.
- Updated the main module card to a Control Center-like layout with quick actions directly on the first screen.
- Replaced the quick progress bar with a clickable shade gamut generated from the current color for faster selection.
- Unified main-menu and detail swatch rendering so both screens show the exact same alternative color gamut.
- Updated quick action controls so eyedropper and copy use rounded-square button styling for visual consistency with detail controls.
- Improved app termination UX by adding a confirmation dialog when quitting the app.
- Optimized Cursor Wrap tracking timer from 120Hz to 60Hz to reduce CPU and battery usage.
- Renamed MouseUtilities module to FindMyMouse for better clarity.

### Fixed
- Fixed Screen Ruler measurement lines to perfectly align with edges by removing the 4px cursor offset.
- Fixed Screen Ruler measurement values to be exact by removing the extra +1px padding.
- Fixed Screen Ruler to allow clicking on other apps and its own settings (including the color picker) while active.
- Fixed remaining legacy naming references in project metadata, scripts, and release links after the rebrand.
- Mouse Highlighter and Crosshairs overlays now work correctly across all connected monitors.
- Find My Mouse spotlight now tracks the cursor accurately on external displays.
- Fixed Find My Mouse spotlight gradient to prevent dark fringes on non-black backgrounds.
- Fixed Screen Ruler permission logic to properly handle asynchronous permission requests.

### Security
- Re-enabled App Sandbox and implemented proper Accessibility permission requests for global shortcuts.

## [1.0.0] - 2025-09-17

### Added
- Initial release of Mac PowerToys with Color Picker feature
- Screen color picker with eyedropper tool
- Native macOS color panel integration
- Automatic hex code copying to clipboard
- Support for multiple color formats (HEX, RGB, HSL, HSV)
- Color history functionality (up to 8 colors)
- Color shade variants display
- Menu bar integration
- Audio and haptic feedback
- SwiftUI-based user interface

### Features
- 🎯 Pick colors from anywhere on screen
- 🎨 Use native macOS color picker
- 📋 Auto-copy hex codes to clipboard
- 🎨 View colors in multiple formats
- 📚 Remember color history
- 🌈 See color shades
- ⚡ Quick menu bar access
- 🔊 Feedback on color selection

### Requirements
- macOS 11.0 (Big Sur) or later
- 64-bit Intel or Apple Silicon Mac
