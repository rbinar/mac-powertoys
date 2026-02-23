#!/bin/bash
# create-beautiful-dmg.sh - Enhanced DMG creation script

VERSION=$1
if [ -z "$VERSION" ]; then
    VERSION="1.0.0"
fi

APP_NAME="MacPowertoys"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
APP_PATH="./build/Build/Products/Release/${APP_NAME}.app"

echo "📦 Creating beautiful DMG for version ${VERSION}..."

# Remove old DMG if exists
if [ -f "$DMG_NAME" ]; then
    rm "$DMG_NAME"
fi

# Create clean staging directory
mkdir -p dmg-staging
cp -R "$APP_PATH" dmg-staging/
ln -s /Applications dmg-staging/Applications

# Create DMG with better styling
create-dmg \
  --volname "Mac Powertoys" \
  --window-pos 200 120 \
  --window-size 800 500 \
  --icon-size 120 \
  --icon "${APP_NAME}.app" 200 250 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 600 250 \
  "$DMG_NAME" \
  "dmg-staging/" || {
    echo "❌ Enhanced DMG creation failed, trying basic method..."
    
    # Fallback method
    hdiutil create -volname "Mac Powertoys" \
                   -srcfolder dmg-staging \
                   -ov -format UDZO \
                   "$DMG_NAME"
}

# Clean up staging directory
rm -rf dmg-staging

echo "✅ DMG created: $DMG_NAME"