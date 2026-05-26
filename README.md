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

## Backends

Two paths are planned for AI Q&A:
- **Direct API** — hits Anthropic with the key from `Secrets.swift`.
- **Mac / Claude Code** — POSTs to a Tailscale endpoint on the Mac, which runs
  `claude -p` and consumes Max plan credits instead of API spend.

## Data

- `CapitalGrilleApp/food-menu.json` — bundled menu data.
- `CapitalGrilleApp/dishes/` — dish photos.
- `CapitalGrilleApp/wine-bottles/` — wine bottle photos.
- `recipes-reference.md` — source-of-truth doc for wines + cocktail recipes (not bundled).
