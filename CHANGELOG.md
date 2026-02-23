# Changelog

All notable changes to Mac Powertoys will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added a Mac Powertoys feature hub in the menu bar popover with quick access to modules. 2026-02-23 22:31

### Changed
- Renamed the app and Xcode project from MenuBarColorPicker to MacPowertoys, including targets, scheme references, and bundle identifiers. 2026-02-23 22:31
- Updated the main module card to a Control Center-like layout with quick actions directly on the first screen. 2026-02-23 22:31
- Replaced the quick progress bar with a clickable shade gamut generated from the current color for faster selection. 2026-02-23 22:31
- Unified main-menu and detail swatch rendering so both screens show the exact same alternative color gamut. 2026-02-23 22:31
- Updated quick action controls so eyedropper and copy use rounded-square button styling for visual consistency with detail controls. 2026-02-23 22:31

### Deprecated

### Removed

### Fixed
- Fixed remaining legacy naming references in project metadata, scripts, and release links after the rebrand. 2026-02-23 22:31

### Security

## [1.0.0] - 2025-09-17

### Added
- Initial release of Mac Powertoys with Color Picker feature
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