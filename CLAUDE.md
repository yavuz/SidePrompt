# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

SidePrompt is a macOS 14+ menu-bar (`LSUIElement`) app: a floating panel that captures the text selection from any app via a global gesture, stages it in sections, and copies it back. Swift 6, SwiftUI + AppKit, local JSON storage, no network except the optional Sparkle updater.

## Build & run

The Xcode project is **generated from `project.yml` by XcodeGen**. `project.pbxproj` is committed, but never hand-edit it — change `project.yml` and regenerate:

```bash
xcodegen generate
```

New `.swift` files anywhere under `SidePrompt/` are picked up automatically by the `sources:` glob; they only need `xcodegen generate` to appear in the project.

Debug build + launch:

```bash
xcodegen generate && xcodebuild -scheme SidePrompt -configuration Debug -derivedDataPath build/DerivedData build && open build/DerivedData/Build/Products/Debug/SidePrompt.app
```

Release ZIP/DMG (optionally notarized):

```bash
./scripts/package.sh
```

There is **no test target** and no linter configured; verification means building and exercising the app.

### Accessibility permission (the main dev friction)

The app is useless without Accessibility: `HotKeyManager` needs a `CGEventTap` for the global gesture, and `SelectionReader` needs AX APIs / synthetic `⌘C`. macOS keys that grant to the app's **path and signature**, so every rebuild to a new DerivedData path is a fresh, untrusted binary — the grant must be re-toggled in System Settings → Privacy & Security → Accessibility (remove the stale entry, re-add the new build). `AppDelegate` polls permissions every 1.5s while `AppModel.needsPermissionHelp` is true and surfaces status in the panel.

Signing: `CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM` is not in `project.yml` — set it in Xcode's Signing pane or pass `DEVELOPMENT_TEAM=...` to `xcodebuild`. Hardened runtime is on; the entitlements file is intentionally **empty** — enabling App Sandbox would break both the event tap and selection reading.

## Architecture

### Ownership and wiring

`SidePromptApp` (`@main`) declares only a `Settings` scene — there is no SwiftUI `WindowGroup`. Everything real is owned by `AppDelegate` (`@NSApplicationDelegateAdaptor`), which holds the three singletons injected into every view via `.environment(...)`:

- `QueueStore` — all data + selection state (`@MainActor @Observable`)
- `AppModel` — transient UI state: toast, permission status, `onOpenItemWindow` / `onRecheck` callbacks
- `ShortcutSettings` — user gesture prefs, persisted to `UserDefaults` under `shortcutSettings.v1`; its `onChange` re-installs the event tap

Windows are AppKit, hosting SwiftUI: `FloatingPanelController` builds the non-activating `NSPanel` (floating level, all Spaces, transparent titlebar) around `PanelRootView`; `ItemWindowManager` opens per-item detail `NSWindow`s keyed by item UUID. Because the panel is movable by window background, interactive regions must opt out with `.disablesWindowDrag()` (`WindowDragGuard`).

### Input: two separate keyboard paths

1. **Global** — `HotKeyManager` creates a `listenOnly` `CGEventTap` on `.flagsChanged` + `.keyDown`. Modifier double-taps (Shift/Option/Control, 0.35s window) fire capture; the panel shortcut is matched by keycode + flags. It re-enables itself on `tapDisabledByTimeout`. Callbacks hop to `@MainActor` via `DispatchQueue.main.async { Task { @MainActor ... } }` because the class is `@unchecked Sendable`.
2. **In-app** — `KeyCommandRouter` is installed as an `NSEvent.addLocalMonitorForEvents(.keyDown)` monitor by `AppDelegate`, not as SwiftUI commands. It bails out (returns the event unhandled) whenever a text field/`NSTextView` is first responder, so ⌘C/⌘A behave normally while editing. Esc first ends editing, then hides the panel.

### Capture pipeline

`SelectionReader.captureSelection()` is `async` and tries, in order:

1. **Clipboard synthesis** (preferred, because it preserves formatting): snapshot the pasteboard → post a synthetic `⌘C` with flags forced to Command only (leftover Shift from the double-tap must not leak) → poll `changeCount` for up to 0.45s → read RTF, then RTFD, then HTML, then plain → **restore the original pasteboard**. Skipped entirely when SidePrompt is frontmost, or the synthetic `⌘C` lands in our own panel.
2. **Accessibility API** — focused element's `kAXSelectedText`, then value+`kAXSelectedTextRange`, then the parent element.

The `changeCount` wait must stay `await Task.sleep`, never `Thread.sleep`: this runs on the main actor, and blocking it freezes the UI *and* can get the event tap killed with `tapDisabledByTimeout`.

### Rich text: `body` vs `bodyRTF`

Every `PromptItem` stores Markdown in `body` (used for search, list rendering, merges, plain copy) and optional lossless `bodyRTF` from the source app. `RichTextMarkdown` converts both ways. Rules that hold across the codebase:

- Plain-text edits (`updateBody(id:body:)`) **clear** `bodyRTF`; attributed edits regenerate both.
- `PasteboardService` copies `bodyRTF` when present, falling back to Markdown; multi-item copies degrade to joined plain text.
- `PromptItem.attributedBody` is the single accessor for display — RTF if available, else Markdown rendered.

### Persistence and schema evolution

The whole `AppStoreData` is written atomically as ISO-8601 JSON to `~/Library/Application Support/SidePrompt/store.json`. Every mutation calls `save()`, but that only **schedules** the write: a 400 ms debounce, then the encode + write happen on the `StoreWriter` actor, off the main thread. Errors land in `lastError` rather than throwing.

Because writes are deferred, anything that can lose them must flush: `flushPendingWrites()` (synchronous, via `LocalStore.save`) runs on `applicationWillTerminate` and `applicationDidResignActive`. Add a flush to any new teardown path.

Rich-text editing is buffered the same way. `updateBody(id:attributed:)` only stashes the `NSAttributedString`; the O(document) Markdown + RTF conversion runs in `commitPendingRichEdits()` after a 350 ms pause, or immediately when a detail window closes. `item.body` is therefore briefly stale while typing — that is intentional, don't "fix" it by converting eagerly.

New optional fields must be added with a hand-written `init(from:)` using `decodeIfPresent` (see `PromptItem.bodyRTF` and `AppStoreData.templates`), so existing stores keep loading.

### Store invariants

- An "Inbox" section always exists (`ensureInbox()`); captures land there. It cannot be deleted, and deleting any section moves its items to Inbox.
- `order` is a dense per-section integer; `moveItems` rewrites orders across sections and `renumber` compacts them. Display order = section order, then item order — `displayOrderedItems()` is the authority for range selection and ordered copies.
- Selection lives in the store (`selectedItemIDs`, `selectionAnchorID`), not in the views, so the key router and the list agree. `editingItemID` marks inline editing and must be cleared by any operation that mutates selection.
- `layoutVersion` is bumped only by mutations that change membership or ordering; the list animates off it instead of hashing every item ID per render.

## Keeping the list cheap

`QueueView` re-renders on every selection change and on every mouse move during a drag, so anything O(items) in a `body` is multiplied by the render rate. The existing shape avoids that and should be preserved:

- Render all sections from one `store.groupedItems()` call, never `store.items(in:)` in a loop.
- Keep `store.orderedIDs` / display-order work inside gesture closures (`onDrag`), not in `body` — `ItemDragPayloadModifier` takes `payload` as a closure for exactly this reason.
- `MarkdownBody` renders through `MarkdownRenderCache`; `AttributedString(markdown:)` is too slow to call per render.

## Conventions

- Everything user-facing is `@MainActor`; `QueueStore`, `AppModel`, `ShortcutSettings`, `AppDelegate` are `@MainActor @Observable` — read via `@Environment(Type.self)`, and use `@Bindable var x = x` inside the body for two-way bindings.
- Feedback is a toast (`appModel.showToast`), never an alert or dialog.
- Sparkle is opt-in: `UpdateManager` stays disabled while `SUPublicEDKey` in `Info.plist` is the `REPLACE_WITH...` placeholder, and never auto-starts in DEBUG. `docs/appcast.xml` and `docs/install.sh` are unwired placeholders.
- Keep it local-first: no analytics, no accounts, no network calls beyond the updater feed.
