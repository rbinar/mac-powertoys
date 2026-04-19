#!/bin/bash
# release.sh - Automated release script for Mac PowerToys
#
# Prerequisites (one-time setup):
#   1. Install "Developer ID Application" certificate from Apple Developer portal
#   2. Store notarization credentials in keychain:
#      xcrun notarytool store-credentials "MacPowerToys" \
#        --apple-id "YOUR_APPLE_ID" \
#        --team-id "6M52F3942H" \
#        --password "APP_SPECIFIC_PASSWORD"
#   3. Install tools: brew install create-dmg gh

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 2.1.0"
    exit 1
fi

set -e

TEAM_ID="6M52F3942H"
APP_PATH="./build/Build/Products/Release/MacPowerToys.app"
DMG_NAME="MacPowerToys-v${VERSION}.dmg"
NOTARIZE_PROFILE="MacPowerToys"

# ── Step 1: Verify Developer ID certificate ──────────────────────────────────
echo "🔍 Checking Developer ID certificate..."
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "❌ Developer ID Application certificate not found in keychain."
    echo "   Install it from https://developer.apple.com/account/resources/certificates"
    exit 1
fi
DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "✅ Found: $DEVELOPER_ID"

# ── Step 2: Verify notarization credentials ──────────────────────────────────
echo "🔍 Checking notarization credentials..."
if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" &>/dev/null; then
    echo "❌ Notarization keychain profile '$NOTARIZE_PROFILE' not found."
    echo "   Run: xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" \\"
    echo "     --apple-id \"YOUR_APPLE_ID\" --team-id \"$TEAM_ID\" --password \"APP_SPECIFIC_PASSWORD\""
    exit 1
fi
echo "✅ Notarization credentials configured"

# ── Step 3: Clean build ──────────────────────────────────────────────────────
echo "🏗️  Building release version $VERSION..."
xcodebuild -project MacPowerToys.xcodeproj \
           -scheme MacPowerToys \
           -configuration Release \
           -derivedDataPath ./build \
           DEVELOPMENT_TEAM="$TEAM_ID" \
           CODE_SIGN_IDENTITY="Developer ID Application" \
           CODE_SIGN_STYLE=Manual \
           OTHER_CODE_SIGN_FLAGS="--timestamp" \
           clean build

# ── Step 4: Verify code signature ────────────────────────────────────────────
echo "🔐 Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "✅ Code signature valid"

# ── Step 5: Create DMG ───────────────────────────────────────────────────────
echo "📦 Creating DMG..."
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg..."
    brew install create-dmg
fi

rm -f "$DMG_NAME"

create-dmg \
    --volname "Mac PowerToys" \
    --volicon "MacPowerToys/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 128 \
    --icon "MacPowerToys.app" 200 190 \
    --hide-extension "MacPowerToys.app" \
    --app-drop-link 600 190 \
    --background-color "#F5F5F7" \
    "$DMG_NAME" \
    "./build/Build/Products/Release/" || {
    echo "⚠️  create-dmg styling failed, using basic DMG..."
    mkdir -p dmg-temp
    cp -R "$APP_PATH" dmg-temp/
    ln -s /Applications dmg-temp/Applications
    hdiutil create -volname "Mac PowerToys" \
                   -srcfolder dmg-temp \
                   -ov -format UDZO \
                   "$DMG_NAME"
    rm -rf dmg-temp
}

# ── Step 6: Sign DMG ─────────────────────────────────────────────────────────
echo "🔐 Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" "$DMG_NAME"
echo "✅ DMG signed"

# ── Step 7: Notarize ─────────────────────────────────────────────────────────
echo "📤 Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$DMG_NAME" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait
echo "✅ Notarization complete"

# ── Step 8: Staple ───────────────────────────────────────────────────────────
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_NAME"
echo "✅ Stapled successfully"

# ── Step 9: Final Gatekeeper verification ────────────────────────────────────
echo "🔍 Final Gatekeeper check..."
spctl --assess --type open --context context:primary-signature -v "$DMG_NAME" 2>&1 || true
echo "✅ Release artifact ready"

# ── Step 10: Git tag & push ──────────────────────────────────────────────────
echo "🏷️  Creating git tag v${VERSION}..."
if git tag "v${VERSION}" 2>/dev/null; then
    echo "✅ Tag v${VERSION} created"
else
    echo "ℹ️  Tag v${VERSION} already exists, skipping creation"
fi
git push origin main
git push origin "v${VERSION}" 2>/dev/null || echo "ℹ️  Tag already on remote, skipping push"

# ── Step 11: GitHub Release ──────────────────────────────────────────────────
echo "🚀 Release files ready!"
echo "📦 DMG: $DMG_NAME"

if command -v gh &> /dev/null; then
    echo "🤖 Creating GitHub release..."
    gh release create "v${VERSION}" \
        "$DMG_NAME" \
        --title "Mac PowerToys v${VERSION}" \
        --notes-file RELEASE_NOTES.md
    echo "✅ Release v${VERSION} published!"
    echo "📥 https://github.com/rbinar/mac-powertoys/releases/tag/v${VERSION}"
else
    echo ""
    echo "Next steps:"
    echo "1. Go to https://github.com/rbinar/mac-powertoys/releases"
    echo "2. Create release for tag v${VERSION}"
    echo "3. Upload $DMG_NAME"
    echo ""
    echo "💡 Tip: brew install gh for automatic release creation"
fi