#!/usr/bin/env bash
# Build → archive → export → upload Capital Grille to TestFlight in one shot.
# Bumps CURRENT_PROJECT_VERSION automatically (App Store requires every upload
# to have a higher build number than the last).
set -euo pipefail

cd "$(dirname "$0")/.."

KEY_ID="P8Y337A8RC"
ISSUER_ID="141a8ead-b829-4e58-b9ff-b8c95f8c4ed9"
ARCHIVE_PATH="/tmp/CapitalGrille.xcarchive"
EXPORT_PATH="/tmp/CapitalGrille-export"
EXPORT_OPTIONS="/tmp/CapitalGrille-ExportOptions.plist"

# --- bump build number in project.yml ---
current=$(awk '/^[[:space:]]+CURRENT_PROJECT_VERSION:/ {gsub(/"/,"",$2); print $2; exit}' project.yml)
next=$((current + 1))
echo "▸ bumping CURRENT_PROJECT_VERSION: $current → $next"
# replace ALL CURRENT_PROJECT_VERSION lines (one per target — must stay in lockstep)
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/g" project.yml

# --- regenerate project + archive ---
echo "▸ xcodegen"
xcodegen generate >/dev/null

echo "▸ archiving (Release)"
rm -rf "$ARCHIVE_PATH"
xcodebuild -project CapitalGrille.xcodeproj -scheme CapitalGrille \
    -destination "generic/platform=iOS" -configuration Release \
    -archivePath "$ARCHIVE_PATH" archive \
    -quiet

# --- export ---
cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>export</string>
    <key>teamID</key><string>XMH4AVFC78</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>uploadBitcode</key><false/>
</dict>
</plist>
PLIST

echo "▸ exporting IPA"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -quiet

# --- upload ---
echo "▸ uploading to App Store Connect"
xcrun altool --upload-app \
    -f "$EXPORT_PATH/CapitalGrille.ipa" \
    -t ios \
    --apiKey "$KEY_ID" \
    --apiIssuer "$ISSUER_ID"

echo "✓ done — build $next is uploading. Check App Store Connect → TestFlight in ~10 min."
