# Changelog (Archive)

This file contains archived changelog entries. See [CHANGELOG.md](CHANGELOG.md) for recent changes.

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
