import Foundation
import SwiftUI
import AppKit

@MainActor
final class ColorModel: ObservableObject {
    @Published var nsColor: NSColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1) {
        didSet {
            // Automatically copy hex code to clipboard when color changes
            copyHexToClipboard()
            // Add to color history
            addToHistory(nsColor)
        }
    }
    
    @Published var colorHistory: [NSColor] = []
    private let maxHistoryCount = 8

    // Screen color picker
    func pickFromScreen() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] picked in
            guard let self, let picked else { return }
            self.nsColor = picked.usingColorSpace(.sRGB) ?? picked
        }
    }
    
    // Open native color panel
    func openColorPanel() {
        let colorPanel = NSColorPanel.shared
        
        // Check if panel is already open
        if colorPanel.isVisible {
            colorPanel.orderOut(nil)
            return
        }
        
        colorPanel.color = nsColor
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorChanged(_:)))
        
        // Panel settings
        colorPanel.showsAlpha = false  // Hide Alpha/Opacity slider
        colorPanel.mode = .wheel  // Use color wheel mode
        colorPanel.hidesOnDeactivate = false  // Allow manual closing
        colorPanel.isFloatingPanel = true    // Make floating panel
        colorPanel.level = .floating         // Set panel level
        
        // Position panel at center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = colorPanel.frame.size
            let centerX = screenFrame.midX - panelSize.width / 2
            let centerY = screenFrame.midY - panelSize.height / 2
            colorPanel.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }
        
        colorPanel.orderFront(nil)
    }
    
    @objc private func colorChanged(_ sender: NSColorPanel) {
        nsColor = sender.color
    }
    
    // Close color panel
    func closeColorPanel() {
        let colorPanel = NSColorPanel.shared
        colorPanel.orderOut(nil)
        colorPanel.setTarget(nil)
        colorPanel.setAction(nil)
    }
    
    // Automatically copies hex code to clipboard
    private func copyHexToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(hexString, forType: .string)
        
        // Visual and audio feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        NSSound.beep() // System sound effect
    }
    
    // Adds to color history
    private func addToHistory(_ color: NSColor) {
        // Don't add if same color already exists
        if let existingIndex = colorHistory.firstIndex(where: { isSimilarColor($0, color) }) {
            colorHistory.remove(at: existingIndex)
        }
        
        // Insert at beginning
        colorHistory.insert(color, at: 0)
        
        // Remove last elements if exceeding maximum count
        if colorHistory.count > maxHistoryCount {
            colorHistory = Array(colorHistory.prefix(maxHistoryCount))
        }
    }
    
    // Checks if two colors are similar
    private func isSimilarColor(_ color1: NSColor, _ color2: NSColor) -> Bool {
        let c1 = color1.usingColorSpace(.sRGB) ?? color1
        let c2 = color2.usingColorSpace(.sRGB) ?? color2
        
        let threshold: CGFloat = 0.01
        return abs(c1.redComponent - c2.redComponent) < threshold &&
               abs(c1.greenComponent - c2.greenComponent) < threshold &&
               abs(c1.blueComponent - c2.blueComponent) < threshold
    }
    
    // Select color from history
    func selectFromHistory(_ color: NSColor) {
        nsColor = color
    }

    // Formatted strings
    var hexString: String {
        let (r,g,b,_) = ColorMath.rgba(nsColor)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        let (r,g,b,_) = ColorMath.rgba(nsColor)
        return "rgb(\(r), \(g), \(b))"
    }

    var hslString: String {
        let (h,s,l) = ColorMath.hsl(nsColor)
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h, s*100, l*100)
    }

    var hsvString: String {
        let (h,s,v) = ColorMath.hsv(nsColor)
        return String(format: "hsv(%.0f, %.0f%%, %.0f%%)", h, s*100, v*100)
    }

    // Copy function
    func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        
        // Visual and audio feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        NSSound.beep() // System sound effect
    }
}

/// Color math helpers
enum ColorMath {
    /// Returns hex string
    static func hexString(_ color: NSColor) -> String {
        let (r,g,b,_) = rgba(color)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    /// Returns RGBA in 0-255 range
    static func rgba(_ color: NSColor) -> (Int, Int, Int, Int) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return (Int(round(c.redComponent * 255)),
                Int(round(c.greenComponent * 255)),
                Int(round(c.blueComponent * 255)),
                Int(round(c.alphaComponent * 255)))
    }

    /// HSL (H:0-360, S/L:0-1)
    static func hsl(_ color: NSColor) -> (Double, Double, Double) {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let maxc = max(r,g,b), minc = min(r,g,b)
        let delta = maxc - minc

        var h: Double = 0
        if delta != 0 {
            if maxc == r { h = 60 * fmod(((g - b) / delta), 6) }
            else if maxc == g { h = 60 * (((b - r) / delta) + 2) }
            else { h = 60 * (((r - g) / delta) + 4) }
        }
        if h < 0 { h += 360 }

        let l = (maxc + minc) / 2
        let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
        return (Double(h), Double(s), Double(l))
    }

    /// HSV (H:0-360, S/V:0-1)
    static func hsv(_ color: NSColor) -> (Double, Double, Double) {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let maxc = max(r,g,b), minc = min(r,g,b)
        let delta = maxc - minc

        var h: Double = 0
        if delta != 0 {
            if maxc == r { h = 60 * fmod(((g - b) / delta), 6) }
            else if maxc == g { h = 60 * (((b - r) / delta) + 2) }
            else { h = 60 * (((r - g) / delta) + 4) }
        }
        if h < 0 { h += 360 }

        let s = maxc == 0 ? 0 : delta / maxc
        let v = maxc
        return (Double(h), Double(s), Double(v))
    }

    /// Generate dark-light shades from left to right
    static func shades(of color: NSColor, count: Int) -> [NSColor] {
        let (_, _, v) = hsv(color)
        return (0..<count).map { i in
            // Navigate value (brightness) in 0.15…1.0 range
            let t = Double(i) / Double(max(count - 1, 1))
            let newV = 0.15 + (v * 0.85) * t
            let (h, s, _) = hsv(color)
            return NSColor(hue: CGFloat(h/360), saturation: CGFloat(s), brightness: CGFloat(newV), alpha: 1)
        }
    }
}
