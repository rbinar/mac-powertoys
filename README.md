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

### 📋 Clipboard Manager
- 📝 **History Tracking**: Keeps a history of your copied text and images
- 🔍 **Searchable**: Quickly find past clipboard items
- 📌 **Pin Items**: Pin important items so they are never deleted
- ⌨️ **Global Shortcut**: Access your clipboard history instantly with `⌃⌥V`
- ⚙️ **Customizable Limit**: Choose how many items to keep in history (10, 25, 50, or 100)

### ☕ Awake
- 🚫 **Prevent Sleep**: Keep your Mac awake indefinitely or for a specific duration
- 🖥️ **Display Control**: Choose whether to keep the display on or just the system awake
- ⏱️ **Timed Mode**: Set a timer (15m, 30m, 1h, 2h, 4h) to automatically allow sleep after the duration

### 🖱️ Mouse Jiggler
- 🏃 **Stay Active**: Simulates tiny, invisible mouse movements to prevent "Away" status in apps like Teams, Slack, and Zoom
- ⚙️ **Adjustable Interval**: Customize how often the mouse jiggles (10s to 120s)

### ⌨️ Markdown Preview
- 👁️ **Live Preview**: Open and preview Markdown files in a resizable window with GitHub-flavored styling
- 📄 **PDF Export**: Export your Markdown as PDF directly from the preview window toolbar
- 📋 **Paste from Clipboard**: Preview Markdown content pasted from clipboard without opening a file
- 🌗 **Theme Toggle**: Switch between light and dark themes for comfortable reading
- 📂 **Recent Files**: Quick access to recently opened Markdown files
- 🔄 **Auto-Reload**: Preview updates automatically when the file changes on disk

### 🍅 Pomodoro Timer
- ⏱️ **Focus Cycles**: Improve productivity with customizable focus and break sessions
- 🔔 **Smart Notifications**: macOS notifications alert you when a phase completes
- 🔄 **Auto-Transitions**: Optional automatic starts for breaks and subsequent focus sessions
- 📊 **Session Tracking**: Track completed focus sessions and total daily progress
- 🎨 **Visual Progress**: Clean UI with dynamic color-coded countdown ring
- 🔊 **Sound Alerts**: Optional sound feedback at the end of each session

### ✍️ Screen Annotation
- 🖌️ **Draw on Screen**: Annotate your screen with freehand, lines, arrows, rectangles, ellipses, and text (Global Shortcut: `⌃⌥D`)
- 🎨 **Color & Width**: Choose from preset colors and adjust line width on the fly
- 🌑 **Dim Background**: Optionally dim the screen for better annotation visibility
- ↩️ **Undo**: Undo drawings with `⌘Z` or right-click
- ⌨️ **Text Tool**: Add text annotations directly on screen
### 🎬 Video Converter
- 🔄 **FFmpeg-Powered**: Convert between 16 formats — 9 video (MP4, MOV, M4V, MKV, WEBM, AVI, FLV, WMV, 3GP), 6 audio (MP3, AAC, WAV, FLAC, M4A, OGG), and animated GIF
- 🎚️ **Quality Presets**: Choose from Low, Medium, High, or Highest quality with automatic codec tuning
- 📐 **Resolution Options**: Original, 4K, 1440p, 1080p, 720p, 480p, or 360p output
- 🎞️ **GIF Creation**: High-quality two-pass GIF generation with palette optimization
- 🎵 **Audio Extraction**: Extract audio tracks from video files into MP3, AAC, FLAC, WAV, M4A, or OGG
- 📊 **Real-time Progress**: Live progress bar parsed from FFmpeg output with elapsed time display
- 📂 **Drag & Drop**: Drop files directly onto the converter or browse with a file picker
- 🔍 **File Analysis**: Automatic metadata extraction (duration, resolution, codec, frame rate, file size)
- 📜 **Conversion History**: View recent conversions with quick "Show in Finder" access
- ⏹️ **Cancel Support**: Cancel running conversions at any time
- 🍺 **One-Click FFmpeg Install**: Detects Homebrew and offers one-click FFmpeg installation with live progress
- 💾 **Persistent Settings**: Selected format, quality, and resolution preferences are saved between sessions

### 🔔 Webhook Notifier
- 📡 **Real-time Notifications**: Receive and display macOS notifications instantly via webhooks
- 🔔 **Custom Topics**: Subscribe to specific topics and filter notifications
- 💬 **ntfy Compatible**: Uses the open-source `ntfy` protocol. Works with any ntfy server (defaults to `https://ntfy.blinkbrosai.com`)
- 🚀 **Easy Integration**: Trigger notifications with a simple HTTP POST request:
  ```bash
  curl -d "Build failed!" https://ntfy.blinkbrosai.com/YOUR_TOPIC_ID
  ```
- ⚙️ **Configurable**: Enable or disable specific webhooks as needed

### General
- ⚡ **Menu Bar Integration**: Quick access from the menu bar with a Control Center style hub
- 🔊 **Audio Feedback**: Haptic and sound feedback when colors are picked
- 🧩 **Extensible Architecture**: Ready for new tools and utilities

## 📋 Requirements

- **macOS 15.5 or later** (Note: This is a significant update from the previous 11.0+ requirement)
- Apple Silicon or Intel Mac
- **FFmpeg** (optional, required for Video Converter — installable via Homebrew from within the app)

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
   - `⌃⌥V` (Control+Option+V): Open Clipboard Manager
   - `⌃⌥D` (Control+Option+D): Toggle Screen Annotation
   - `Double Left Control`: Find My Mouse
   - `Double Left Option`: Mouse Highlighter
   - `Double Right Option`: Mouse Crosshairs
   - **Cursor Wrap**: Enable from the Mouse Utilities menu to teleport cursor across screen edges
4. **Awake & Mouse Jiggler**:
   - Enable **Awake** to prevent your Mac from sleeping (choose indefinite or set a timer)
   - Enable **Mouse Jiggler** to simulate mouse movements and stay active in communication apps
5. **Clipboard Manager**:
   - Enable to start tracking your clipboard history
   - Use `⌃⌥V` to quickly access your history from anywhere
   - Click an item to copy it back to your clipboard
   - Pin important items to keep them permanently
6. **Color Picker**:
   - Click the eyedropper button and use it on screen
   - Click the color circle to open native color picker
   - View HEX, RGB, HSL, and HSV representations
   - Access previously picked colors from history
7. **Screen Annotation**:
   - Enable and press `⌃⌥D` to enter annotation mode
   - Use the toolbar to switch between freehand, line, arrow, rectangle, ellipse, and text tools
   - Right-click or `⌘Z` to undo, `Esc` to close
8. **Webhook Notifier**:
   - Add custom topics to receive real-time notifications
   - Trigger notifications using HTTP POST requests (e.g., `curl -d "Message" https://ntfy.blinkbrosai.com/TOPIC_ID`)
   - Click on notifications to view details
   - Toggle specific webhooks on or off as needed
9. **Pomodoro Timer**:
   - Enable to start a 25-minute focus session
   - Automatically transitions to a 5-minute break (customizable)
   - Tracks your daily completed sessions with visual indicators
10. **Video Converter**:
   - Requires FFmpeg (one-click install via Homebrew if available)
   - Drag & drop or browse for a video/audio file
   - Select output format (video, audio, or GIF), quality, and resolution
   - Choose save location and start conversion with real-time progress
   - View conversion history and reveal output files in Finder

## 🛠️ Development

This app is built with:
- **SwiftUI** for the user interface
- **AppKit** for macOS integration
- **NSColorSampler** for screen color picking
- **NSColorPanel** for native color selection
- **AVFoundation** for media file analysis
- **FFmpeg** (via NSUserUnixTask) for video/audio conversion

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⭐ Support

If you find this app useful, please consider giving it a star on GitHub!