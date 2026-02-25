# Changelog

All notable changes to Mac PowerToys will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added Screen Recording permission check and alert for the Screen Ruler feature. 2026-02-26 00:45
- Added a Mac PowerToys feature hub in the menu bar popover with quick access to modules. 2026-02-23 22:31
- Added Mouse Utilities module with four features: Find My Mouse, Mouse Highlighter, Mouse Crosshairs, and Cursor Wrap. 2026-02-24 12:55
- Find My Mouse dims all screens and spotlights the cursor when activated via double-tap Left Control. 2026-02-24 12:55
- Mouse Highlighter draws colored circles on left/right clicks to highlight cursor activity. 2026-02-24 12:55
- Mouse Crosshairs shows a full-screen crosshair overlay that follows the cursor. 2026-02-24 12:55
- Cursor Wrap teleports the cursor to the opposite screen edge when it hits a boundary. 2026-02-24 12:55
- Global keyboard shortcuts for all Mouse Utilities features work without Accessibility permission. 2026-02-24 12:55

### Changed
- Renamed the app and Xcode project from MenuBarColorPicker to MacPowerToys, including targets, scheme references, and bundle identifiers. 2026-02-23 22:31
- Updated the main module card to a Control Center-like layout with quick actions directly on the first screen. 2026-02-23 22:31
- Replaced the quick progress bar with a clickable shade gamut generated from the current color for faster selection. 2026-02-23 22:31
- Unified main-menu and detail swatch rendering so both screens show the exact same alternative color gamut. 2026-02-23 22:31
- Updated quick action controls so eyedropper and copy use rounded-square button styling for visual consistency with detail controls. 2026-02-23 22:31

### Deprecated

### Removed

### Fixed
- Fixed Screen Ruler measurement lines to perfectly align with edges by removing the 4px cursor offset. 2026-02-26 00:45
- Fixed Screen Ruler measurement values to be exact by removing the extra +1px padding. 2026-02-26 00:45
- Fixed Screen Ruler to allow clicking on other apps and its own settings (including the color picker) while active. 2026-02-26 00:45
- Fixed remaining legacy naming references in project metadata, scripts, and release links after the rebrand. 2026-02-23 22:31
- Mouse Highlighter and Crosshairs overlays now work correctly across all connected monitors. 2026-02-24 12:55
- Find My Mouse spotlight now tracks the cursor accurately on external displays. 2026-02-24 12:55

### Security

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