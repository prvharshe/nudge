# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This is a pure Xcode project with no external package managers.

```bash
# Build for simulator (Debug)
xcodebuild -scheme nudge -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build

# Run tests
xcodebuild -scheme nudge -destination 'platform=iOS Simulator,name=iPhone 16' test

# Clean build
xcodebuild -scheme nudge clean
```

Open `nudge.xcodeproj` in Xcode for GUI development and simulator runs.

## Architecture

SwiftUI + SwiftData iOS app (deployment target: iOS 26.2+).

- **`nudgeApp.swift`** — App entry point. Configures the `ModelContainer` with the `Item` schema and wraps `ContentView` in a `WindowGroup`.
- **`Item.swift`** — The sole SwiftData model, marked `@Model`. Currently has a single `timestamp: Date` property.
- **`ContentView.swift`** — Main UI using `NavigationSplitView` for master-detail layout. Uses `@Query` for reactive data, `@Environment(\.modelContext)` for persistence operations.

### Key Patterns
- Data persistence via SwiftData (`@Model`, `@Query`, `ModelContainer`)
- UI reactivity via SwiftUI's `@Environment` and `@Query` property wrappers
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide
- Bundle ID: `com.ph.nudge`
