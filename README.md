# ⚙️ Mac PowerToys

A collection of powerful utilities for macOS, accessible from your menu bar. Inspired by Microsoft PowerToys.

![Mac PowerToys](https://img.shields.io/badge/macOS-15.5+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ Features

### 🎨 Color Picker
- 🎯 **Screen Color Picker**: Use the eyedropper tool to pick any color from your screen (Global Shortcut: `⌃⌥C`)
- 🎨 **Native Color Panel**: Access macOS's built-in color picker
- 📋 **Auto-Copy**: Hex codes are automatically copied to clipboard
- 🎨 **Multiple Formats**: Support for HEX, RGB, HSL, and HSV color formats
- 📚 **Color History**: Keep track of your recently picked colors (up to 8)
- 🌈 **Color Shades**: See color variations and shades

### 📏 Screen Ruler
- 📐 **Measure Anything**: Measure pixels between elements on your screen (Global Shortcut: `⌃⌥R`)
- 🎯 **Smart Edge Detection**: Automatically snaps to edges of windows and UI elements
- 📏 **Multiple Modes**: Measure bounds, spacing, horizontal, or vertical distances
- 📋 **Quick Copy**: Click to copy measurements to clipboard

### 🔍 ZoomIt
- 🔎 **Screen Zoom**: Statically magnify your screen and pan around smoothly (Global Shortcut: `⌃⌥Z`)
- 🎥 **Live Zoom**: Real-time magnification that follows your cursor (Global Shortcut: `⌃⌥L`)
- ⚙️ **Adjustable Zoom**: Use scroll wheel to adjust magnification level dynamically

### 🖱️ Mouse Utilities
- 🔦 **Find My Mouse**: Dims the screen and spotlights your cursor (Double-tap `Left Control`)
- 🖍️ **Mouse Highlighter**: Visual indicators for left and right mouse clicks (Double-tap `Left Option`)
- ➕ **Mouse Crosshairs**: Full-screen crosshairs centered on your cursor (Double-tap `Right Option`)
- 🔄 **Cursor Wrap**: Teleport your cursor to the opposite screen edge when hitting a boundary

### General
- ⚡ **Menu Bar Integration**: Quick access from the menu bar with a Control Center style hub
- 🔊 **Audio Feedback**: Haptic and sound feedback when colors are picked
- 🧩 **Extensible Architecture**: Ready for new tools and utilities

## 📋 Requirements

- **macOS 15.5 or later** (Note: This is a significant update from the previous 11.0+ requirement)
- Apple Silicon or Intel Mac

## 🚀 Installation

### Download from Releases
1. Download the latest `MacPowerToys.dmg` from [Releases](https://github.com/rbinar/mac-powertoys/releases)
2. Open the DMG file
3. Drag `MacPowerToys.app` to your Applications folder
4. Launch from Applications or Spotlight

### ⚠️ Security Notice (First Launch)
Since this app is not notarized by Apple, you may see a security warning on first launch:
1. If you see **"MacPowerToys" Cannot Be Opened**, click **"OK"**
2. Go to **System Preferences > Security & Privacy > General**
3. Click **"Open Anyway"** next to the blocked app message
4. Click **"Open"** in the confirmation dialog

This is a one-time setup - the app will launch normally afterwards.

### Build from Source
```bash
git clone https://github.com/rbinar/mac-powertoys.git
cd mac-powertoys
open MacPowerToys.xcodeproj
```

## 🎯 Usage

1. **Launch the app** - The wrench icon will appear in your menu bar
2. **Click the menu bar icon** to open the Mac PowerToys feature hub
3. **Select a tool** from the feature list or use global shortcuts:
   - `⌃⌥C` (Control+Option+C): Launch Color Picker
   - `⌃⌥R` (Control+Option+R): Toggle Screen Ruler
   - `⌃⌥Z` (Control+Option+Z): Toggle Screen Zoom
   - `⌃⌥L` (Control+Option+L): Toggle Live Zoom
   - `Double Left Control`: Find My Mouse
   - `Double Left Option`: Mouse Highlighter
   - `Double Right Option`: Mouse Crosshairs
4. **Color Picker**:
   - Click the eyedropper button and use it on screen
   - Click the color circle to open native color picker
   - View HEX, RGB, HSL, and HSV representations
   - Access previously picked colors from history

## 🛠️ Development

This app is built with:
- **SwiftUI** for the user interface
- **AppKit** for macOS integration
- **NSColorSampler** for screen color picking
- **NSColorPanel** for native color selection

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⭐ Support

If you find this app useful, please consider giving it a star on GitHub!