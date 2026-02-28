# Troubleshooting: Silent Shell Script Execution and App Sandbox

## The Problem
When attempting to silently install and execute a shell script (e.g., `ffmpeg-runner.sh`) in the background using `NSUserUnixTask` inside a macOS Sandboxed app, the execution strictly fails. 

Typical errors include:
- `"The file couldn’t be opened because you don’t have permission to view it."`
- `"Unknown interpreter"` error from `NSUserUnixTask`.

### Why does this happen?
Apple's App Sandbox enforces extremely strict security rules against executing dynamically written code:
1. **Quarantine Attribute**: When a sandboxed app writes a file to disk, macOS automatically applies a Gatekeeper `com.apple.quarantine` extended attribute.
2. **Execution Block**: Even if you bypass the quarantine by programmatically running `removexattr(path, "com.apple.quarantine", 0)` and assigning `0o755` permissions, the Sandbox kernel will explicitly deny execution of a script *unless* the user was explicitly prompted to save the file via an `NSSavePanel` (Save File Dialog).

**Conclusion:** It is impossible to achieve "silent installation and background execution" of a helper script within a strict App Sandbox environment without showing a prompt to the user first.

## The Solution
For utilities (like MacPowerToys) that require deep system access (global hotkeys, mouse tracking, background script execution), the App Sandbox is often too restrictive. The solution for non-Mac App Store (MAS) distribution (e.g., GitHub, DMG) is to disable the Sandbox.

### Steps to Fix:
1. Open the project's entitlements file (e.g., `MacPowertoys.entitlements`).
2. Locate the `com.apple.security.app-sandbox` key.
3. Set its value to `<false/>` (or remove it).

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/> <!-- Ensure this is set to false -->
    ...
</dict>
```

With the Sandbox disabled, the app can freely use `Process()` or `NSUserUnixTask` to silently write, evaluate, and execute scripts in `~/Library/Application Scripts/` or any other appropriate directory without interrupting the user experience.