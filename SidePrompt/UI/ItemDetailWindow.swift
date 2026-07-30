import AppKit
import SwiftUI

/// The detail window is a fixed light surface (#fdfdfd) — deliberately not
/// `.windowBackgroundColor`. The window is pinned to the aqua appearance so the
/// system's adaptive text/selection colors stay legible on it in dark mode.
enum PanelSurface {
    static let nsColor = NSColor(srgbRed: 253 / 255, green: 253 / 255, blue: 253 / 255, alpha: 1)
    static let color = Color(nsColor: nsColor)

    /// Hairline used for the header / footer rules.
    static let rule = Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07))

    @MainActor
    static var appearance: NSAppearance? {
        NSAppearance(named: .aqua)
    }
}

/// Opens (or focuses) a dedicated editing window for long item bodies.
@MainActor
final class ItemWindowManager {
    static let shared = ItemWindowManager()

    private var windows: [UUID: NSWindow] = [:]
    private var closeProxies: [UUID: WindowCloseProxy] = [:]
    private weak var store: QueueStore?
    private weak var appModel: AppModel?

    func configure(store: QueueStore, appModel: AppModel) {
        self.store = store
        self.appModel = appModel
        Self.purgeLegacyFrameAutosaves()
    }

    /// Earlier builds keyed the frame autosave name by item UUID, leaving one
    /// permanent UserDefaults entry per item ever opened.
    private static func purgeLegacyFrameAutosaves() {
        let defaults = UserDefaults.standard
        let prefix = "NSWindow Frame SidePrompt.ItemDetail."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    func open(itemID: UUID) {
        guard let store, let appModel else { return }
        guard store.items.contains(where: { $0.id == itemID }) else { return }

        if let existing = windows[itemID] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ItemDetailView(itemID: itemID)
            .environment(store)
            .environment(appModel)

        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = PanelSurface.nsColor.cgColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "SidePrompt"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // No Dock icon in an accessory app, so a minimised window is hard to get back.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.minSize = NSSize(width: 400, height: 320)
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.appearance = PanelSurface.appearance
        window.backgroundColor = PanelSurface.nsColor
        window.isOpaque = true
        window.animationBehavior = .documentWindow
        window.center()
        window.setFrameAutosaveName("SidePrompt.ItemDetail")

        let proxy = WindowCloseProxy { [weak self] in
            // Rich-text edits are debounced in the store — flush before the view goes away.
            self?.store?.commitPendingRichEdits()
            self?.windows.removeValue(forKey: itemID)
            self?.closeProxies.removeValue(forKey: itemID)
        }
        window.delegate = proxy
        closeProxies[itemID] = proxy
        windows[itemID] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(itemID: UUID) {
        windows[itemID]?.close()
        windows.removeValue(forKey: itemID)
        closeProxies.removeValue(forKey: itemID)
    }

    /// Takes the text directly so typing doesn't trigger a store lookup per keystroke.
    func refreshTitle(for itemID: UUID, text: String) {
        guard let window = windows[itemID] else { return }
        let trimmed = text.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            window.title = "SidePrompt"
            return
        }
        let flattened = trimmed.replacingOccurrences(of: "\n", with: " ")
        window.title = flattened.count <= 120 ? flattened : String(flattened.prefix(117)) + "..."
    }
}

private final class WindowCloseProxy: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - View

struct ItemDetailView: View {
    @Environment(QueueStore.self) private var store
    let itemID: UUID

    @State private var attributed = NSAttributedString(string: "")
    @State private var justCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var item: PromptItem? {
        store.items.first(where: { $0.id == itemID })
    }

    private var isDone: Bool {
        item?.isDone == true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            rule

            RichTextEditor(attributedText: $attributed)
                .onChange(of: attributed) { _, newValue in
                    store.updateBody(id: itemID, attributed: newValue)
                    ItemWindowManager.shared.refreshTitle(for: itemID, text: newValue.string)
                }
                .onDisappear {
                    copyResetTask?.cancel()
                    store.commitPendingRichEdits()
                }

            rule
            footer
        }
        .background(PanelSurface.color)
        .onAppear(perform: loadFromStore)
    }

    private var rule: some View {
        Rectangle()
            .fill(PanelSurface.rule)
            .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            // Left side stays empty — that space belongs to the traffic lights.
            Spacer(minLength: 0)

            DetailToolButton(
                systemName: isDone ? "checkmark.circle.fill" : "checkmark.circle",
                tint: isDone ? Color.accentColor : Color.secondary,
                help: isDone ? "Mark Incomplete" : "Mark Done"
            ) {
                store.toggleDone(id: itemID)
            }

            DetailToolButton(
                systemName: justCopied ? "checkmark" : "doc.on.doc",
                tint: justCopied ? Color.accentColor : Color.secondary,
                help: "Copy (⌘⇧C)"
            ) {
                copy()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(countsLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if isDone {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.accentColor.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    private var countsLabel: String {
        let characters = attributed.length
        guard characters > 0 else { return "Empty" }
        let words = Self.wordCount(in: attributed.string)
        let wordLabel = words == 1 ? "word" : "words"
        let charLabel = characters == 1 ? "character" : "characters"
        return "\(words) \(wordLabel) · \(characters) \(charLabel)"
    }

    /// Allocation-free — this runs on every keystroke.
    private static func wordCount(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    private func copy() {
        guard PasteboardService.copy(attributed) else { return }
        justCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            justCopied = false
        }
    }

    private func loadFromStore() {
        guard let item else {
            attributed = NSAttributedString(string: "")
            return
        }
        attributed = item.attributedBody
    }
}

/// Borderless icon button with a soft hover pill.
private struct DetailToolButton: View {
    let systemName: String
    let tint: Color
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Text editor

/// NSTextView wrapper so the detail window shows formatting, not `**` markers.
private struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString

    private static let bodyFont = NSFont.systemFont(ofSize: 14)

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 9
        return style
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let surface = PanelSurface.nsColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = surface
        scroll.scrollerKnobStyle = .default
        scroll.appearance = PanelSurface.appearance

        let textView = DetailTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = surface
        textView.appearance = PanelSurface.appearance
        textView.font = Self.bodyFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.typingAttributes = [
            .font: Self.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Self.paragraphStyle,
        ]
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedText)

        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let surface = PanelSurface.nsColor
        scrollView.backgroundColor = surface
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.backgroundColor = surface
        guard !context.coordinator.isEditing else { return }
        if textView.string != attributedText.string
            || textView.attributedString().length != attributedText.length {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            pushChange()
        }

        func textDidChange(_ notification: Notification) {
            pushChange()
        }

        private func pushChange() {
            guard let textView, let storage = textView.textStorage else { return }
            parent.attributedText = NSAttributedString(attributedString: storage)
        }
    }
}

/// Keeps the text surface on panel gray #fdfdfd (avoids system white textBackgroundColor).
private final class DetailTextView: NSTextView {
    override var backgroundColor: NSColor {
        get { PanelSurface.nsColor }
        set { super.backgroundColor = PanelSurface.nsColor }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        drawsBackground = true
        backgroundColor = PanelSurface.nsColor
        enclosingScrollView?.backgroundColor = PanelSurface.nsColor
        enclosingScrollView?.drawsBackground = true
    }

    /// Esc closes the window. Without this the global key router would treat it as
    /// "hide the floating panel" whenever focus sits outside the text view.
    override func cancelOperation(_ sender: Any?) {
        window?.performClose(nil)
    }

    /// Accessory apps have no menu bar, so ⌘W has to be wired up by hand.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            window?.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
