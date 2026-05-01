# EPS Quick Look

EPS Quick Look is a macOS app and Quick Look extension for previewing EPS and
PostScript files in Finder.

## What It Does

- Adds Quick Look preview support for `.eps`, `.epsf`, `.epsi`, and `.ps`
- Renders previews through the bundled Ghostscript parser
- Supports Sparkle-powered app updates
- Includes a small settings window for app preferences and acknowledgements

## Project Structure

- `App/` — macOS app source, assets, entitlements, and acknowledgements
- `Extensions/Preview/` — Quick Look preview extension
- `Extensions/Thumbnail/` — Quick Look thumbnail extension
- `Shared/` — Swift sources reused by the app and both extensions
- `Resources/` — bundled Ghostscript parser shared by the extensions
- `Tests/` — unit tests for shared parsing and settings helpers
- `EPS Quick Look.xcodeproj/` — Xcode project

## Development

1. Open `EPS Quick Look.xcodeproj` in Xcode.
2. Build and run the app target.
3. Enable both Quick Look extensions in System Settings under General >
   Login Items & Extensions > Extensions > Quick Look.

## Third-Party Software

This project bundles Ghostscript for preview rendering and uses Sparkle for
software updates.
See `App/Acknowledgments.txt` for licensing and attribution details.
