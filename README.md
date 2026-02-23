# ⚙️ Mac Powertoys

A collection of powerful utilities for macOS, accessible from your menu bar. Inspired by Microsoft PowerToys.

![Mac Powertoys](https://img.shields.io/badge/macOS-15.5+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ Features

### 🎨 Color Picker
- 🎯 **Screen Color Picker**: Use the eyedropper tool to pick any color from your screen
- 🎨 **Native Color Panel**: Access macOS's built-in color picker
- 📋 **Auto-Copy**: Hex codes are automatically copied to clipboard
- 🎨 **Multiple Formats**: Support for HEX, RGB, HSL, and HSV color formats
- 📚 **Color History**: Keep track of your recently picked colors (up to 8)
- 🌈 **Color Shades**: See color variations and shades

### General
- ⚡ **Menu Bar Integration**: Quick access from the menu bar
- 🔊 **Audio Feedback**: Haptic and sound feedback when colors are picked
- 🧩 **Extensible Architecture**: Ready for new tools and utilities

## 📋 Requirements

- macOS 15.5 or later
- Apple Silicon or Intel Mac

## 🚀 Installation

### Download from Releases
1. Download the latest `MacPowertoys.dmg` from [Releases](https://github.com/rbinar/mac-powertoys/releases)
2. Open the DMG file
3. Drag `MacPowertoys.app` to your Applications folder
4. Launch from Applications or Spotlight

### ⚠️ Security Notice (First Launch)
Since this app is not notarized by Apple, you may see a security warning on first launch:
1. If you see **"MacPowertoys" Cannot Be Opened**, click **"OK"**
2. Go to **System Preferences > Security & Privacy > General**
3. Click **"Open Anyway"** next to the blocked app message
4. Click **"Open"** in the confirmation dialog

This is a one-time setup - the app will launch normally afterwards.

### Build from Source
```bash
git clone https://github.com/rbinar/mac-powertoys.git
cd mac-powertoys
open MacPowertoys.xcodeproj
```

## 🎯 Usage

1. **Launch the app** - The wrench icon will appear in your menu bar
2. **Click the menu bar icon** to open Mac Powertoys
3. **Select a tool** from the feature list
4. **Color Picker**:
   - Click "Pick" button and use eyedropper on screen
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