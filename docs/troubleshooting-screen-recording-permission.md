# Screen Recording Permission — Troubleshooting Guide

## Problem

Screen Ruler (and potentially other features using `SCShareableContent` / `SCScreenshotManager`) may show a **"Screen Recording Permission Required"** alert even when the user has already granted permission. The toggle may also fail to stay in the **enabled** state.

## Root Cause

### 1. Catch-all error handling treats every failure as a permission issue

`SCShareableContent.excludingDesktopWindows()` and `SCScreenshotManager.captureImage()` can throw errors for reasons **other than** missing permissions — for example, transient ScreenCaptureKit errors, display reconfiguration, or race conditions on wake from sleep.

If the `catch` block blindly assumes every error is a permission problem and sets `isEnabled = false`, the toggle bounces back to off even though permission is granted.

**Fix:** Check `CGPreflightScreenCaptureAccess()` inside the catch block before showing the permission alert. Only disable the feature if permission is truly missing:

```swift
} catch {
    if capturedScreens.isEmpty {
        if !CGPreflightScreenCaptureAccess() {
            // Show permission alert + open System Settings
        }
        isEnabled = false
    }
}
```

### 2. Task continues after `isEnabled` is set to false

The `activate()` method sets `isActive = true` and launches an async `Task` that calls `captureScreensAsync()`. If capture fails and sets `isEnabled = false` (which triggers `deactivate()`), the Task may continue to execute `createOverlayWindows()`, `showToolbar()`, etc., leaving orphaned windows.

**Fix:** Add a guard after `captureScreensAsync()`:

```swift
Task {
    await captureScreensAsync()
    guard isEnabled else { return }  // bail if capture disabled us
    createOverlayWindows()
    showToolbar()
    // ...
}
```

## Key APIs

| API | Purpose | Notes |
|-----|---------|-------|
| `CGPreflightScreenCaptureAccess()` | Check if screen recording permission is granted | Does NOT trigger a permission prompt. Safe to call anytime. Returns `Bool`. |
| `CGRequestScreenCaptureAccess()` | Request permission (shows system dialog) | Only shows dialog once. Avoid calling repeatedly — it triggers a system alert each time on some macOS versions. |
| `SCShareableContent.excludingDesktopWindows()` | Get available displays/windows | Throws if permission is missing **or** on transient errors. Don't rely on this alone for permission checking. |
| `SCScreenshotManager.captureImage()` | Capture a screenshot of a display | Can fail for individual displays even when permission is granted. |

## Diagnostic Checklist

1. **Is permission actually granted?**
   - Check `CGPreflightScreenCaptureAccess()` — should return `true`
   - Verify in System Settings → Privacy & Security → Screen Recording

2. **Is `SCShareableContent` returning displays?**
   - Log `content.displays.count` after the call
   - If 0 displays, it might be a transient issue

3. **Is `SCScreenshotManager.captureImage()` failing for specific displays?**
   - Log per-display capture results
   - Partial failures (some displays captured, some not) should not disable the feature

4. **Is `isEnabled` being set to `false` unexpectedly?**
   - Add a print in `isEnabled.didSet` to trace who toggles it
   - Check if `deactivate()` is being called before the Task completes

## Debug Logging (temporary)

When investigating, add these prints:

```swift
// In activate()
print("[ScreenRuler] activate() called, isActive=\(isActive), isEnabled=\(isEnabled)")

// In captureScreensAsync()
print("[ScreenRuler] CGPreflightScreenCaptureAccess() = \(CGPreflightScreenCaptureAccess())")
print("[ScreenRuler] SCShareableContent: \(content.displays.count) displays")
print("[ScreenRuler] capture result for display \(display.displayID): success/fail")

// In catch block
print("[ScreenRuler] Error: \(error)")
print("[ScreenRuler] Error type: \(type(of: error))")
```

## Related Files

- `MacPowerToys/Features/ScreenRuler/ScreenRulerModel.swift` — `activate()`, `captureScreensAsync()`
- `MacPowerToys/Features/ScreenRuler/ScreenRulerView.swift` — Toggle binding to `isEnabled`

## History

- **2026-02-27:** Fixed catch-all error handling + added `guard isEnabled` bailout after capture.
