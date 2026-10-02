# Capital Grille — iOS Reference App

SwiftUI iPhone app for navigating The Capital Grille menu (food, wines, cocktails) and asking
freeform questions about it via Claude Haiku.

## Setup

1. Copy `CapitalGrilleApp/Secrets.swift.example` to `CapitalGrilleApp/Secrets.swift`
   and paste your Anthropic API key. `Secrets.swift` is gitignored.
2. Generate the Xcode project:
   ```
   xcodegen generate
   ```
3. Open `CapitalGrille.xcodeproj` and run.

## Assistant

AI Q&A goes straight to the Anthropic API, with the key entered in Settings on the phone (synced to the watch).

## Data

- `CapitalGrilleApp/food-menu.json` — bundled menu data.
- `CapitalGrilleApp/dishes/` — dish photos.
- `recipes-reference.md` — source-of-truth doc for wines + cocktail recipes (not bundled).
