# Changelog

All notable changes to Mac PowerToys will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added Markdown Preview module with live preview of `.md` files in a resizable window 2026-02-27 05:00.
- PDF export for Markdown files directly from the preview window toolbar 2026-02-27 05:00.
- Paste from Clipboard support to preview markdown content without opening a file 2026-02-27 05:00.
- Light/Dark theme toggle for Markdown Preview 2026-02-27 05:00.
- Recent files list with security-scoped bookmarks for persistent sandbox access 2026-02-27 05:00.
- Auto-reload when the previewed markdown file changes on disk 2026-02-27 05:00.
- Added Clipboard Manager module to track copied text and images with searchable history (`⌃⌥V`) 2026-02-27 04:05.
- Pin important clipboard items to keep them permanently 2026-02-27 04:05.
- Adjustable history limit (10, 25, 50, or 100 items) for Clipboard Manager 2026-02-27 04:05.
- Added Awake module to prevent Mac from sleeping with indefinite and timed modes 2026-02-27 01:10.
- Added Keep Display On option to Awake module to prevent screen sleep 2026-02-27 01:10.
- Added Mouse Jiggler module to simulate tiny mouse movements and prevent "Away" status in apps like Teams and Slack 2026-02-27 01:10.
- Added adjustable interval setting (10s-120s) for Mouse Jiggler 2026-02-27 01:10.
- Added Webhook Notifier module to receive and display real-time notifications instantly 2026-02-26 12:00.
- Added ability to subscribe to specific topics and filter notifications in Webhook Notifier 2026-02-26 12:00.
- Added interactive alerts for webhook notifications to take action directly 2026-02-26 12:00.
- Added toggle to enable or disable specific webhooks as needed 2026-02-26 12:00.
- Added ZoomIt module with Screen Zoom (⌃⌥Z) and Live Zoom (⌃⌥L) features 2026-02-26 03:48.
- Screen Zoom allows static magnification of the screen with smooth panning 2026-02-26 03:48.
- Live Zoom provides real-time magnification following the cursor using high-performance ScreenCaptureKit 2026-02-26 03:48.
- Global keyboard shortcut ⌃⌥C (Control+Option+C) to launch the Color Picker screen sampler from anywhere 2026-02-26 03:48.
- Global keyboard shortcut ⌃⌥R (Control+Option+R) to toggle Screen Ruler on/off from anywhere 2026-02-26 03:48.
- ESC key closes the Screen Ruler overlay when active 2026-02-26 03:48.
- Added Screen Recording permission check and alert for the Screen Ruler feature 2026-02-26 03:48.
- Added a Mac PowerToys feature hub in the menu bar popover with quick access to modules 2026-02-26 03:48.
- Added Mouse Utilities module with four features: Find My Mouse, Mouse Highlighter, Mouse Crosshairs, and Cursor Wrap 2026-02-26 03:48.
- Find My Mouse dims all screens and spotlights the cursor when activated via double-tap Left Control 2026-02-26 03:48.
- Mouse Highlighter draws colored circles on left/right clicks to highlight cursor activity 2026-02-26 03:48.
- Mouse Crosshairs shows a full-screen crosshair overlay that follows the cursor 2026-02-26 03:48.
- Cursor Wrap teleports the cursor to the opposite screen edge when it hits a boundary 2026-02-26 03:48.
- Global keyboard shortcuts for all Mouse Utilities features now require Accessibility permission 2026-02-26 03:48.

### Changed
- Redesigned feature hub as a compact 2-column grid layout for better space utilization 2026-02-27 04:05.
- Menu bar popover height now adjusts automatically based on content instead of a fixed max height 2026-02-26 03:48.
- Module cards show a lighter hover effect on mouse-over for better interactivity feedback 2026-02-26 03:48.
- Color Picker eyedropper and copy buttons are now circular instead of rounded squares 2026-02-26 03:48.
- Mouse Utilities module icon changed from "cursorarrow.rays" to a simpler "cursorarrow" 2026-02-26 03:48.
- Renamed the app and Xcode project from MenuBarColorPicker to MacPowerToys, including targets, scheme references, and bundle identifiers 2026-02-26 03:48.
- Updated the main module card to a Control Center-like layout with quick actions directly on the first screen 2026-02-26 03:48.
- Replaced the quick progress bar with a clickable shade gamut generated from the current color for faster selection 2026-02-26 03:48.
- Unified main-menu and detail swatch rendering so both screens show the exact same alternative color gamut 2026-02-26 03:48.
- Updated quick action controls so eyedropper and copy use rounded-square button styling for visual consistency with detail controls 2026-02-26 03:48.
- Improved app termination UX by adding a confirmation dialog when quitting the app 2026-02-26 03:48.
- Optimized Cursor Wrap tracking timer from 120Hz to 60Hz to reduce CPU and battery usage 2026-02-26 03:48.
- Renamed MouseUtilities module to FindMyMouse for better clarity 2026-02-26 03:48.

### Deprecated

### Removed

### Fixed
- Fixed Screen Ruler measurement lines to perfectly align with edges by removing the 4px cursor offset 2026-02-26 03:48.
- Fixed Screen Ruler measurement values to be exact by removing the extra +1px padding 2026-02-26 03:48.
- Fixed Screen Ruler to allow clicking on other apps and its own settings (including the color picker) while active 2026-02-26 03:48.
- Fixed remaining legacy naming references in project metadata, scripts, and release links after the rebrand 2026-02-26 03:48.
- Mouse Highlighter and Crosshairs overlays now work correctly across all connected monitors 2026-02-26 03:48.
- Find My Mouse spotlight now tracks the cursor accurately on external displays 2026-02-26 03:48.
- Fixed Find My Mouse spotlight gradient to prevent dark fringes on non-black backgrounds 2026-02-26 03:48.
- Fixed Screen Ruler permission logic to properly handle asynchronous permission requests 2026-02-26 03:48.

### Security
- Re-enabled App Sandbox and implemented proper Accessibility permission requests for global shortcuts 2026-02-26 03:48.

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