#!/bin/bash
# release.sh - Automated release script for Mac PowerToys

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh 1.0.0"
    exit 1
fi

set -e

echo "🏗️  Building release version $VERSION..."

# Clean ve build
xcodebuild -project MacPowerToys.xcodeproj \
           -scheme MacPowerToys \
           -configuration Release \
           -derivedDataPath ./build \
           clean build

echo "🔐 Code signing (optional)..."
# Code sign the app if Developer ID is available
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "📝 Developer ID found, signing application..."
    DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    codesign --force --options runtime --sign "$DEVELOPER_ID" \
             "./build/Build/Products/Release/MacPowerToys.app"
    echo "✅ Application signed with: $DEVELOPER_ID"
else
    echo "⚠️  No Developer ID found - app will show security warning on other Macs"
    echo "   Users can bypass this via System Preferences > Security & Privacy"
fi

echo "📦 Creating DMG..."

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg..."
    brew install create-dmg
fi

# DMG oluştur
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
  "MacPowerToys-v${VERSION}.dmg" \
  "./build/Build/Products/Release/" || {
    echo "DMG creation failed, trying alternative method..."
    # Alternative DMG creation
    mkdir -p dmg-temp
    cp -R "./build/Build/Products/Release/MacPowerToys.app" dmg-temp/
    ln -s /Applications dmg-temp/Applications
    hdiutil create -volname "Mac PowerToys" \
                   -srcfolder dmg-temp \
                   -ov -format UDZO \
                   "MacPowerToys-v${VERSION}.dmg"
    rm -rf dmg-temp
}

echo "🏷️  Creating git tag..."

# Git tag oluştur ve push et
git add .
git commit -m "Add release documentation and scripts" || true
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

echo "🚀 Release files ready!"
echo "📦 DMG file: MacPowerToys-v${VERSION}.dmg"
echo "📝 Release notes: RELEASE_NOTES.md"
echo ""
echo "Next steps:"
echo "1. Go to https://github.com/rbinar/mac-powertoys/releases"
echo "2. Click 'Create a new release'"
echo "3. Choose tag v${VERSION}"
echo "4. Upload MacPowerToys-v${VERSION}.dmg"
echo "5. Copy content from RELEASE_NOTES.md"
echo "6. Publish release!"

# If GitHub CLI is available, create release automatically
if command -v gh &> /dev/null; then
    echo ""
    echo "🤖 GitHub CLI detected. Creating release automatically..."
    gh release create "v${VERSION}" \
        "MacPowerToys-v${VERSION}.dmg" \
        --title "Mac PowerToys v${VERSION}" \
        --notes-file RELEASE_NOTES.md
    echo "✅ Release v${VERSION} published successfully!"
    echo "📥 Download: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name")/releases/tag/v${VERSION}"
else
    echo ""
    echo "💡 Tip: Install GitHub CLI for automatic release creation:"
    echo "   brew install gh"
fi