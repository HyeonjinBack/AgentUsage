#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${BUILD_CONFIGURATION:-release}"
scratch="${AGENTMETER_SCRATCH:-.build}"
swift build -c "$configuration" --scratch-path "$scratch" --disable-sandbox -debug-info-format none --product AgentMeter
binary_dir="$(swift build -c "$configuration" --scratch-path "$scratch" --show-bin-path)"
app="dist/AgentMeter.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/AgentMeter" "$app/Contents/MacOS/AgentMeter"
resource_bundle="$binary_dir/AgentMeter_AgentMeter.bundle"
if [ -d "$resource_bundle" ]; then
    mkdir -p "$app/Contents/Resources"
    ditto "$resource_bundle" "$app/Contents/Resources/AgentMeter_AgentMeter.bundle"
fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentMeter</string>
<key>CFBundleIdentifier</key><string>dev.agentmeter.local</string>
<key>CFBundleName</key><string>AgentMeter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app (local ad-hoc signature)"
