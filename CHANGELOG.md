# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · [SemVer](https://semver.org/)

## [Unreleased]

### Added
- Video Converter module: FFmpeg-powered conversion between 16 formats (MP4, MOV, MKV, WEBM, AVI, MP3, AAC, WAV, FLAC, GIF, etc.) with quality presets, resolution options, and real-time progress. 2026-02-28 14:00
- Drag & drop file input and one-click FFmpeg installation via Homebrew in Video Converter. 2026-02-28 14:00
- Conversion history with "Show in Finder" for recent outputs in Video Converter. 2026-02-28 14:00
- Scrollable content areas in Color Picker, Crosshairs, Find My Mouse, Mouse Highlighter, Screen Annotation, Screen Ruler, and main hub views. 2026-02-28 14:00
- PR code review fixes documentation under `docs/pr-review-fixes.md`. 2026-02-27 12:00
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
- Improved error logging across Webhook Notifier, Clipboard Manager, and Markdown Preview with proper do-catch blocks. 2026-02-27 12:00
- Replaced `DispatchQueue.main.asyncAfter` with structured `Task.sleep` in Clipboard Manager. 2026-02-27 12:00
- Clipboard Manager icon updated from `doc.on.clipboard` to `list.clipboard`. 2026-02-28 14:00
- Menu bar popover now has a fixed height (340×560) for consistent layout. 2026-02-28 14:00
- Accessibility permission prompt only appears if not already granted, avoiding repeated dialogs. 2026-02-28 14:00
- App Sandbox disabled to support FFmpeg execution via NSUserUnixTask. 2026-02-28 14:00
- Bundle version bumped to 2. 2026-02-28 14:00

### Deprecated

### Removed

### Fixed
- Fixed Screen Ruler measurement lines to perfectly align with edges by removing the 4px cursor offset.
- Fixed Screen Ruler measurement values to be exact by removing the extra +1px padding.
- Fixed Screen Ruler to allow clicking on other apps and its own settings (including the color picker) while active.
- Fixed remaining legacy naming references in project metadata, scripts, and release links after the rebrand.
- Mouse Highlighter and Crosshairs overlays now work correctly across all connected monitors.
- Find My Mouse spotlight now tracks the cursor accurately on external displays.
- Fixed Find My Mouse spotlight gradient to prevent dark fringes on non-black backgrounds.
- Fixed Screen Ruler permission logic to properly handle asynchronous permission requests.
- Fixed Webhook Notifier to properly buffer streaming data and handle partial messages. 2026-02-27 12:00
- Fixed Clipboard Manager global hotkey not being released on app termination. 2026-02-27 12:00
- Fixed Markdown Preview crash on files with uncommon extensions due to force-unwrapped UTType. 2026-02-27 12:00
- Fixed Markdown Preview unreliable rendering by replacing timer delay with WKNavigationDelegate. 2026-02-27 12:00
- Fixed Markdown Preview toolbar delegate singleton causing potential ownership issues. 2026-02-27 12:00
- Fixed Screen Annotation event handlers firing twice due to duplicate local and global monitors. 2026-02-27 12:00
- Fixed Screen Annotation screenshot now captures all connected displays instead of only the primary. 2026-02-27 12:00

### Security
- Re-enabled App Sandbox and implemented proper Accessibility permission requests for global shortcuts.
- Added DOMPurify sanitization to Markdown Preview to prevent XSS in rendered HTML. 2026-02-27 12:00
- Fixed path traversal vulnerability in Clipboard Manager image file handling. 2026-02-27 12:00
- Removed sensitive topic identifiers from Webhook Notifier console logs. 2026-02-27 12:00

> Older releases archived in [CHANGELOG-2.md](CHANGELOG-2.md).
- 64-bit Intel or Apple Silicon Mac