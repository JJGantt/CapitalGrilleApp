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

## In-app AI assistant — two backends
`ChatEngine.swift`'s AI chat has **two backends**, chosen by `Backend.current` (`MacClient.swift`); iOS defaults to **`.mac`**:
- **`.mac`** → routes through the Mac (`MacClient.ask`), which runs `claude -p` with an MCP server. The bottle tools are a Python MCP at **`~/scripts/capital_grille_wine_mcp.py`** (`mcp__bottle__*`). Default path for the phone. MCP reloads per session, so edits take effect next request.
- **`.api`** (and the Mac-unreachable fallback) → direct Anthropic API via `AnthropicClient.chatWithTools`, using the **local `AnthropicTool` handlers in ChatEngine.swift**.

**Any tool change must be mirrored in BOTH** the Python MCP and the Swift handlers to keep parity.

The **system prompt** is built in-app (`buildPromptAndTools`) and sent to both backends. Editable rule blocks live **remotely in Supabase `app_content` (key=`system_prompt`, JSON `data`: restock/food_menu/base_rules/catalog_rules/cocktail_routing)** and **override** the in-code fallbacks; they use `{{tool}}`/`{{data}}` placeholders resolved at runtime. Update the remote block to change live behavior. The **catalog skeleton** injected into the cached prompt prefix is built dynamically from `bottleStore` — enrich it by editing `formatBottle`, no data migration. All app content (bottles, pairings, glossary, descriptions, views) is backend data: adding/editing content needs no rebuild; only a new grouping FIELD or new UI/tool needs a build.

## Bottle / wine / liquor data model
**Liquor and wine group differently** because their data has different shapes:
- **Wine** — two *orthogonal* view axes (separate toggles): "Type" (group_by `varietal`/`category`) and "Style" (group_by `pairing_style`). A style like "Structured Bold Red" crosses varietals, so style is NOT a subset of type — independent filters.
- **Liquor** — a single *nested* two-level tree in "Type" view: spirit **type → style (varietal) → bottle**. Style is a strict subset of type (every Bourbon is a Whiskey). The type→style mapping lives in the backend **`spirit_types`** table (varietal, type, type_order, style_order) — NOT hardcoded; a varietal with no row defaults to a type equal to itself (Vodka/Tequila render flat). Only **Whiskey** (~84 bottles) and **Brandy** (Cognac + Brandy) actually nest. Type-level umbrella descriptions are `group_descriptions` rows with `dimension='type'` (only "Whiskey" is custom); style-level reuses varietal blurbs. Code: `BottleStore.liquorTypeGroups()` → `[BottleTypeGroup]`; `LiquorListView` renders nested when `group_by == "varietal"`, flat otherwise.

Architecture preference: the **backend is the source of truth**; the app derives structure dynamically from relational data (e.g. a `section_views`/grouping table defines view modes). Do NOT stuff this config into an `app_content` JSON blob — use real relational tables.

## Supabase access (project ref `felyggqjjhltwokdfhop`, "life-data")
- **Data reads/writes** (no DDL): PostgREST `https://felyggqjjhltwokdfhop.supabase.co/rest/v1/` with the service-role key.
- **DDL / arbitrary SQL** (runs as `postgres` superuser): the Management API, authed with the Supabase CLI token in the macOS keychain:
  ```bash
  RAW=$(security find-generic-password -s "Supabase CLI" -w)
  TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
  curl -s -X POST "https://api.supabase.com/v1/projects/felyggqjjhltwokdfhop/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"query":"<SQL HERE>"}'
  ```
  The Supabase CLI (`/opt/homebrew/bin/supabase`) is authenticated and linked (`~/workspace/CapitalGrilleApp/supabase`). `psql` is NOT installed — use the Management API.

## Working agreements (behavioral — these are firm)
- **Bottle catalog (`bottles` table):** NEVER add a bottle on my own initiative or from web research — the only valid reason a bottle exists is "we physically carry it," and only Jared knows that. Adding is allowed ONLY when he explicitly asks. **Editing/correcting and deleting ARE allowed without asking each time, once I've confirmed the facts via sources** (e.g. delete a phantom row, enrich a tasting note). He wants rich, accurate, sourced detail in the data, not thin notes. Phantom rows have null locations; real bottles occupy a shelf slot (primary_area/column/row).
- **Dish questions:** NEVER describe a menu item from generic/"standard" culinary knowledge. Pull the ACTUAL ingredients from `CapitalGrilleApp/food-menu.json` first (Generous Pour items lacking recipe detail usually appear on the regular menu with full `portion`/`description`). Guessing teaches him wrong facts he'll repeat on the floor.
- **Description style (grapes/regions/producers/tasting notes):** write FOR A LEARNER, not an insider. Never use an undefined industry term (DOC/DOCG, AVA, appellation, Charmat, field blend, blanc de blancs, "single varietal", "Mash #1"…) — define it in the same sentence or cut it. Don't lead with shouty EXACT/ESTIMATE labels on wine grapes; convey confidence in plain words ("the winery confirms this exact mix" / "they don't publish amounts, so this is an estimate"). Explain US labeling plainly ("a US wine named for one grape must be ≥75% that grape"). Include all vital info, no padding; clarity over brevity. (Whiskey grain-bill/cask notes keep EXACT/ESTIMATE labels per his earlier explicit request.)
- **TestFlight:** NEVER run `scripts/release.sh` / push a build unless Jared explicitly asks in that moment. Building/compiling to verify is fine; shipping is not. When he's home he builds straight to his phone — an unprompted push wastes a build number and submits a beta review he didn't ask for. After app changes, just report that it builds and offer TestFlight as an option.

## Menu learning notes
Jared bartends at Capital Grille (since 2026-06-12) and is learning the menu (wine, whiskey, pairings). The living study log is at `~/Life/Learn/capital-grille-menu.md` (deliberately separate from this app) — update it as new topics are covered.
