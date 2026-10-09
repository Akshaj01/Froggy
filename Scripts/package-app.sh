#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP="$ROOT/Froggy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$ROOT/.build/release/Froggy" "$APP/Contents/MacOS/Froggy"
chmod +x "$APP/Contents/MacOS/Froggy"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Froggy</string>
	<key>CFBundleIdentifier</key>
	<string>com.froggy.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Froggy</string>
	<key>CFBundleDisplayName</key>
	<string>Froggy</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSAccessibilityUsageDescription</key>
	<string>Froggy uses Accessibility to see which file you drop its tongue on.</string>
	<key>NSScreenCaptureUsageDescription</key>
	<string>Froggy uses Screen Recording to take a screenshot when you double-click the frog.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
