# Capital Grille App

iOS + watchOS app, xcodegen-generated (`project.yml`). Team `XMH4AVFC78`.

## Devices
- iPhone (Jared's iPhone): `43E696C5-1412-5026-BEBF-914C7818B296`
- Watch (Apple Watch SE 3): `15EAAA2F-0775-5655-839A-603F56EC9DE1`

## Build & install
```
cd ~/workspace/CapitalGrilleApp
xcodegen generate                           # only if project.yml changed
xcodebuild -project CapitalGrille.xcodeproj -scheme CapitalGrille \
  -destination "id=43E696C5-1412-5026-BEBF-914C7818B296" -configuration Debug build

# iPhone
xcrun devicectl device install app --device 43E696C5-1412-5026-BEBF-914C7818B296 \
  ~/Library/Developer/Xcode/DerivedData/CapitalGrille-bwvudmifqxrusxbowtqpddxkllbd/Build/Products/Debug-iphoneos/CapitalGrille.app

# Watch (direct, optional — phone install will normally push to watch automatically)
xcrun devicectl device install app --device 15EAAA2F-0775-5655-839A-603F56EC9DE1 \
  ~/Library/Developer/Xcode/DerivedData/CapitalGrille-bwvudmifqxrusxbowtqpddxkllbd/Build/Products/Debug-watchos/CapitalGrilleWatch.app
```

## Watch install gotcha — "Could not install at this time"
Solved 2026-06-01. Root cause: **Developer Mode on the watch is hidden until the system sees a dev-signed install attempt arrive via the direct Mac→Watch CoreDevice channel.** The iPhone→Watch app-relay path silently fails when Dev Mode is off, surfacing as an IDS socket timeout in `appconduitd` logs and a generic "Could not install at this time" dialog. App Store watch apps install fine because they don't need Dev Mode.

### Symptoms when Dev Mode is off on the watch
- Watch app install fails with "Could not install at this time"
- Console.app filtered on `appconduitd` shows: `IDSDeviceConnection has timed out waiting for a socket`, error `ACXErrorDomain Code=8 "Failed to create socket"`, underlying `com.apple.identityservices.error Code=20`
- Settings → Privacy & Security on the watch has no Developer Mode toggle (it's hidden)
- App Store watch apps install fine

### Fix
1. Verify Mac sees the watch in CoreDevice: `xcrun devicectl list devices`. If missing, kick remotepairingd:
   ```
   kill -9 $(launchctl list | awk '$3=="com.apple.CoreDevice.remotepairingd"{print $1}')
   ```
   Watch reappears within 15s as "connecting" → "connected (no DDI)".
2. Run a direct install to the watch UDID (will fail but triggers the dev path):
   ```
   xcrun devicectl device install app --device 15EAAA2F-0775-5655-839A-603F56EC9DE1 .../CapitalGrilleWatch.app
   ```
   Fails with `Developer Mode is disabled` — but the toggle now appears on the watch.
3. On the watch: Settings → Privacy & Security → Developer Mode → ON. Watch restarts.
4. Re-run the install. Works going forward via either direct or iPhone-Watch app path.

## TestFlight release — one-liner
`./scripts/release.sh` does the whole pipeline: bumps `CURRENT_PROJECT_VERSION`, regenerates the Xcode project, archives Release, exports the IPA, and uploads to App Store Connect via the API key already wired in. After ~5-15 min the build shows up in App Store Connect → TestFlight. Add testers under **Internal Testing** (no Apple review) or **External Testing** (24h review on first build).

API key lives at `~/.appstoreconnect/private_keys/AuthKey_P8Y337A8RC.p8` (Key ID `P8Y337A8RC`, Issuer ID `141a8ead-b829-4e58-b9ff-b8c95f8c4ed9`, role: App Manager). If it's ever revoked or rotated, regenerate via App Store Connect → Users and Access → Integrations → App Store Connect API and update the constants at the top of `scripts/release.sh`.

Each TestFlight tester provides their own Anthropic API key in Settings on first launch — the bundled `Secrets.anthropicAPIKey` and the dev-only Keychain seeding are both `#if DEBUG`-gated, so Release builds contain no key. Jared's own devices auto-seed from `Secrets.swift` on debug runs, and that Keychain entry persists into subsequent TestFlight installs of the same bundle ID.

## Architecture notes
- Shared chat engine at `CapitalGrilleApp/ChatEngine.swift` — both iOS and watch use it
- Watch's `MacClient.ask` routes through `WatchPhoneRelay` (WatchConnectivity) when Backend is `.mac`
- Watch defaults to API backend (separate UserDefaults key `backendWatch`); iOS defaults to Mac (`backend`)
- `food-menu.json` bundled in both targets so chat tools can resolve dish lookups offline
