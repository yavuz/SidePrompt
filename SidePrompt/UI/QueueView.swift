import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DropInsertion: Equatable {
    case before(itemID: UUID, sectionID: UUID)
    case end(sectionID: UUID)
}

@MainActor
@Observable
private final class ListDragState {
    var draggingIDs: Set<UUID> = []
    var dropInsertion: DropInsertion?
    private var mouseUpMonitor: Any?

    var isDragging: Bool { !draggingIDs.isEmpty }

    func begin(ids: [UUID]) {
        draggingIDs = Set(ids)
        dropInsertion = nil
        installMouseUpMonitor()
    }

    func clear() {
        draggingIDs = []
        dropInsertion = nil
        removeMouseUpMonitor()
    }

    private func installMouseUpMonitor() {
        removeMouseUpMonitor()
        // Clear on mouse-up immediately. The line must never outlive the drag gesture.
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            DispatchQueue.main.async {
                self?.clear()
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
    }
}

struct QueueView: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @State private var draftSectionTitle = ""
    @State private var isAddingSection = false
    @State private var showTemplates = false
    @State private var saveTemplateTitle = ""
    @State private var showSaveTemplate = false
    @FocusState private var composerFocused: Bool
    @State private var composerText = ""
    @State private var composerSectionId: UUID?
    @State private var dragState = ListDragState()
    @State private var sectionPendingDelete: SectionModel?
    @State private var renameSectionTarget: SectionModel?
    @State private var renameSectionTitle = ""

    private let panelGray = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if appModel.needsPermissionHelp {
                permissionBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
            }

            topBar(store: store)
                .padding(.horizontal, 14)
                .padding(.top, appModel.needsPermissionHelp ? 10 : 16)
                .padding(.bottom, 12)

            listContent

            composer
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .onAppear {
            composerSectionId = store.sortedSections.first?.id
            appModel.refreshAccessibilityStatus()
        }
        .onDisappear {
            dragState.clear()
        }
        .confirmationDialog(
            deleteSectionDialogTitle,
            isPresented: Binding(
                get: { sectionPendingDelete != nil },
                set: { if !$0 { sectionPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Section", role: .destructive) {
                confirmDeleteSection()
            }
            Button("Cancel", role: .cancel) {
                sectionPendingDelete = nil
            }
        } message: {
            Text(deleteSectionDialogMessage)
        }
        .sheet(isPresented: Binding(
            get: { renameSectionTarget != nil },
            set: { if !$0 { renameSectionTarget = nil } }
        )) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Section").font(.headline)
                TextField("Title", text: $renameSectionTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { renameSectionTarget = nil }
                    Button("Save") {
                        if let target = renameSectionTarget {
                            store.renameSection(id: target.id, title: renameSectionTitle)
                        }
                        renameSectionTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 280)
        }
    }

    private var deleteSectionDialogTitle: String {
        if let section = sectionPendingDelete {
            return "Delete “\(section.title)”?"
        }
        return "Delete Section?"
    }

    private var deleteSectionDialogMessage: String {
        guard let section = sectionPendingDelete else { return "" }
        let count = store.items(in: section).count
        if count == 0 {
            return "This section will be removed."
        }
        return "\(count) item(s) will move to Inbox, then the section will be removed."
    }

    private func confirmDeleteSection() {
        guard let section = sectionPendingDelete else { return }
        let moved = store.deleteSection(id: section.id)
        if composerSectionId == section.id {
            composerSectionId = store.sortedSections.first?.id
        }
        if let moved {
            appModel.showToast(moved == 0 ? "Section deleted" : "Moved \(moved) to Inbox")
        }
        sectionPendingDelete = nil
    }

    // MARK: - Top: Search + •••

    private func topBar(store: QueueStore) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search", text: Bindable(store).searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onTapGesture {
                        dismissEditor()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelGray.opacity(0.9), in: Capsule())

            Menu {
                Button("Templates…") { showTemplates = true }
                if !store.selectedItemIDs.isEmpty {
                    Button("Save Selection as Template…") { showSaveTemplate = true }
                }
                Divider()
                Button("Copy as List") { copyList() }
                if store.selectedItemIDs.count >= 2 {
                    Button("Merge Selected") {
                        if store.mergeSelected() != nil {
                            appModel.showToast("Merged")
                        }
                    }
                }
                Divider()
                Button("Add Section…") { isAddingSection = true }
                if store.sortedSections.count > 1 {
                    Picker("Composer section", selection: Binding(
                        get: { composerSectionId ?? store.sortedSections.first?.id },
                        set: { composerSectionId = $0 }
                    )) {
                        ForEach(store.sortedSections) { section in
                            Text(section.title).tag(Optional(section.id))
                        }
                    }
                }
                Divider()
                SettingsLink {
                    Text("Settings…")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(panelGray.opacity(0.9), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .popover(isPresented: $isAddingSection) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New section").font(.headline)
                    TextField("Title", text: $draftSectionTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    HStack {
                        Spacer()
                        Button("Add") {
                            store.addSection(title: draftSectionTitle)
                            draftSectionTitle = ""
                            isAddingSection = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draftSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showTemplates) {
                TemplatesSheet()
                    .environment(store)
                    .environment(appModel)
            }
            .sheet(isPresented: $showSaveTemplate) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Save as Template").font(.headline)
                    TextField("Title", text: $saveTemplateTitle)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Cancel") { showSaveTemplate = false }
                        Button("Save") {
                            if store.saveSelectedAsTemplate(title: saveTemplateTitle) != nil {
                                appModel.showToast("Template saved")
                                saveTemplateTitle = ""
                                showSaveTemplate = false
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(saveTemplateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .frame(width: 320)
            }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions needed")
                .font(.system(size: 12, weight: .semibold))
            Text(appModel.permissionStatusText)
                .font(.system(size: 11, weight: .medium))
            Text("Toggle SidePrompt off/on in Accessibility, then Recheck.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Settings") {
                    AccessibilityPermission.openSystemSettings()
                }
                Button("Recheck") {
                    appModel.onRecheck?()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - List

    private var listContent: some View {
        // Group once per render instead of filtering + sorting per section.
        let grouped = store.groupedItems()

        // The content is stretched to at least the viewport height so clicks in the
        // empty area below the last card still land on a tap target and deselect.
        return GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(store.sortedSections) { section in
                        sectionBlock(section, sectionItems: grouped[section.id] ?? [])
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .frame(
                    maxWidth: .infinity,
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
                .contentShape(Rectangle())
                .onTapGesture { dismissEditor() }
                .animation(.snappy(duration: 0.22), value: store.layoutVersion)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func dismissEditor() {
        store.endEditing()
        store.clearSelection()
        composerFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func sectionBlock(_ section: SectionModel, sectionItems: [PromptItem]) -> some View {
        let sectionHighlighted = isSectionHighlighted(section.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(sectionHighlighted ? Color.accentColor : .secondary)
                    .tracking(0.7)
                Rectangle()
                    .fill(sectionHighlighted ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditor()
            }
            .contextMenu {
                Button("Rename Section…") {
                    renameSectionTarget = section
                    renameSectionTitle = section.title
                }
                if store.canDeleteSection(id: section.id) {
                    Button("Delete Section…", role: .destructive) {
                        sectionPendingDelete = section
                    }
                }
            }

            if sectionItems.isEmpty {
                Text("No items")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        if dragState.isDragging,
                           dragState.dropInsertion == .end(sectionID: section.id) {
                            InsertionLine()
                        }
                    }
                    .onTapGesture { dismissEditor() }
                    .onDrop(
                        of: [.plainText],
                        delegate: SectionEndDropDelegate(
                            sectionID: section.id,
                            dragState: dragState,
                            onDrop: performDrop
                        )
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sectionItems.enumerated()), id: \.element.id) { index, item in
                        if dragState.isDragging,
                           case .before(let itemID, let sectionID) = dragState.dropInsertion,
                           itemID == item.id,
                           sectionID == section.id {
                            InsertionLine()
                                .padding(.vertical, 3)
                        }

                        ItemRow(
                            item: item,
                            isDragPlaceholder: dragState.draggingIDs.contains(item.id),
                            onDragBegan: { ids in
                                dismissEditor()
                                dragState.begin(ids: ids)
                            }
                        )
                        .padding(.vertical, 4)
                        .onDrop(
                            of: [.plainText],
                            delegate: ItemRowDropDelegate(
                                item: item,
                                sectionID: section.id,
                                nextItemID: index + 1 < sectionItems.count ? sectionItems[index + 1].id : nil,
                                dragState: dragState,
                                onDrop: performDrop
                            )
                        )

                        if index == sectionItems.count - 1 {
                            if dragState.isDragging,
                               dragState.dropInsertion == .end(sectionID: section.id) {
                                InsertionLine()
                                    .padding(.vertical, 3)
                            }
                            Color.clear
                                .frame(height: 14)
                                .contentShape(Rectangle())
                                .onTapGesture { dismissEditor() }
                                .onDrop(
                                    of: [.plainText],
                                    delegate: SectionEndDropDelegate(
                                        sectionID: section.id,
                                        dragState: dragState,
                                        onDrop: performDrop
                                    )
                                )
                        }
                    }
                }
            }
        }
    }

    private func isSectionHighlighted(_ sectionID: UUID) -> Bool {
        guard dragState.isDragging else { return false }
        switch dragState.dropInsertion {
        case .before(_, let sid), .end(let sid):
            return sid == sectionID
        case nil:
            return false
        }
    }

    private func performDrop(ids: [UUID], insertion: DropInsertion) {
        dragState.clear()

        let ordered = store.orderedIDs(from: ids)
        guard !ordered.isEmpty else { return }
        withAnimation(.snappy(duration: 0.22)) {
            switch insertion {
            case .before(let itemID, let sectionID):
                store.moveItems(ordered, to: sectionID, before: itemID)
            case .end(let sectionID):
                store.moveItems(ordered, to: sectionID, before: nil)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        let sectionName = store.sortedSections
            .first(where: { $0.id == (composerSectionId ?? store.sortedSections.first?.id) })?
            .title
            .lowercased() ?? "inbox"

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.tertiary)

            TextField(
                "Add a note or a prompt (\(sectionName))",
                text: $composerText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(1...4)
            .focused($composerFocused)
            .onSubmit(submitComposer)
            .onChange(of: composerFocused) { _, focused in
                if focused { store.endEditing() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func submitComposer() {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let sectionId = composerSectionId ?? store.sortedSections.first?.id
        guard let sectionId else { return }
        store.endEditing()
        _ = store.addItem(to: sectionId, body: body, kind: .prompt)
        composerText = ""
        composerFocused = true
    }

    private func copyList() {
        let text = store.copySelectedAsList()
        if PasteboardService.copy(text) {
            appModel.showToast(store.selectedItemIDs.isEmpty ? "Copied as List" : "Copied")
        }
    }
}

// MARK: - Item card

struct ItemRow: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(ShortcutSettings.self) private var shortcuts
    let item: PromptItem
    var isDragPlaceholder: Bool = false
    var onDragBegan: (([UUID]) -> Void)?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private var isEditing: Bool {
        store.editingItemID == item.id
    }

    private var dragIDs: [UUID] {
        if store.selectedItemIDs.contains(item.id), store.selectedItemIDs.count > 1 {
            return store.orderedIDs(from: Array(store.selectedItemIDs))
        }
        return [item.id]
    }

    /// What other apps receive. Reordering inside the panel reads `ListDragState`
    /// instead, so the payload never has to carry item IDs.
    private func makeDragProvider() -> NSItemProvider {
        let dragged = dragIDs.compactMap { id in store.items.first(where: { $0.id == id }) }
        let text = dragged
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let provider = NSItemProvider()
        // RTF first so rich editors get formatting; plain text is the fallback.
        if dragged.count == 1, let rtf = dragged[0].bodyRTF, !rtf.isEmpty {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.rtf.identifier,
                visibility: .all
            ) { completion in
                completion(rtf, nil)
                return nil
            }
        }
        provider.registerObject(text as NSString, visibility: .all)
        return provider
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.endEditing()
                store.toggleDone(id: item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary.opacity(0.75))
            }
            .buttonStyle(.borderless)
            .padding(.top, 1)

            Group {
                if isEditing {
                    TextEditor(text: $draft)
                        .font(.system(size: 13))
                        .frame(minHeight: 44, maxHeight: 140)
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .onExitCommand { commitAndClose() }
                } else {
                    MarkdownBody(text: item.body, isDone: item.isDone, lineLimit: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(isEditing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .shadow(color: .black.opacity(isSelected || isEditing ? 0.08 : 0.05), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: isSelected || isEditing ? 1.5 : 1)
        }
        .opacity(isDragPlaceholder ? 0.35 : 1)
        .animation(.easeOut(duration: 0.15), value: isDragPlaceholder)
        .onTapGesture {
            handleTap()
        }
        // Panel is movable-by-background; without this, grabbing a card moves the window.
        .disablesWindowDrag()
        .modifier(ItemDragPayloadModifier(
            enabled: !isEditing,
            // Evaluated at drag time — computing it in `body` re-sorts the whole
            // list for every row on every render while a multi-selection is active.
            provider: { makeDragProvider() },
            onDragBegan: {
                onDragBegan?(dragIDs)
            }
        ))
        .onChange(of: store.editingItemID) { previous, current in
            if previous == item.id && current != item.id {
                store.updateBody(id: item.id, body: draft)
                editorFocused = false
            }
            if current == item.id {
                draft = item.body
                DispatchQueue.main.async { editorFocused = true }
            }
        }
        .contextMenu {
            Button("Open in Window") {
                store.endEditing()
                appModel.onOpenItemWindow?(item.id)
            }
            Button(isSelected ? "Deselect" : "Select") {
                store.endEditing()
                store.toggleSelection(id: item.id)
            }
            Button("Copy") {
                if PasteboardService.copy(item) {
                    appModel.showToast("Copied")
                }
            }
            Button(item.isDone ? "Mark Incomplete" : "Mark Done") {
                store.toggleDone(id: item.id)
            }
            Button("Edit Inline") { beginEdit() }
            if store.selectedItemIDs.count >= 2 {
                Button("Merge Selected") {
                    if store.mergeSelected() != nil {
                        appModel.showToast("Merged")
                    }
                }
            }
            Divider()
            ForEach(store.sortedSections) { section in
                Button("Move to \(section.title)") {
                    store.moveItem(item.id, to: section.id)
                }
                .disabled(section.id == item.sectionId)
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.delete(ids: [item.id])
                ItemWindowManager.shared.close(itemID: item.id)
            }
        }
    }

    private var isSelected: Bool {
        store.selectedItemIDs.contains(item.id)
    }

    private var cardFill: Color {
        if isSelected || isEditing {
            return Color.accentColor.opacity(0.08)
        }
        return Color(nsColor: .textBackgroundColor)
    }

    private var cardStroke: Color {
        if isSelected || isEditing {
            return Color.accentColor.opacity(0.45)
        }
        return Color.primary.opacity(0.05)
    }

    private func handleTap() {
        // Prefer the click event’s modifiers; fall back to current flags.
        let event = NSApp.currentEvent
        let raw = event?.modifierFlags ?? NSEvent.modifierFlags
        let flags = raw.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            store.endEditing()
            store.toggleSelection(id: item.id)
            return
        }

        if flags.contains(.shift), let anchor = store.selectionAnchorID {
            store.selectRange(from: anchor, to: item.id)
            return
        }

        // Double-click → configured activate action.
        if (event?.clickCount ?? 1) >= 2 {
            activateItem()
            return
        }

        // Single-click → select only (so double-click can open a window cleanly).
        store.endEditing()
        store.selectedItemIDs = [item.id]
        store.selectionAnchorID = item.id
    }

    private func activateItem() {
        switch shortcuts.itemActivateAction {
        case .inlineEdit:
            beginEdit()
        case .openWindow:
            store.endEditing()
            store.selectedItemIDs = [item.id]
            store.selectionAnchorID = item.id
            appModel.onOpenItemWindow?(item.id)
        }
    }

    private func beginEdit() {
        if store.editingItemID == item.id {
            store.selectedItemIDs = [item.id]
            store.selectionAnchorID = item.id
            return
        }
        store.selectedItemIDs = [item.id]
        store.selectionAnchorID = item.id
        draft = item.body
        store.editingItemID = item.id
    }

    private func commitAndClose() {
        store.updateBody(id: item.id, body: draft)
        store.endEditing()
        editorFocused = false
    }
}

private struct ItemDragPayloadModifier: ViewModifier {
    let enabled: Bool
    let provider: () -> NSItemProvider
    let onDragBegan: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                onDragBegan()
                return provider()
            }
        } else {
            content
        }
    }
}

private struct InsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 2)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 3, y: 0)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
    }
}

private struct ItemRowDropDelegate: DropDelegate {
    let item: PromptItem
    let sectionID: UUID
    let nextItemID: UUID?
    let dragState: ListDragState
    let onDrop: @MainActor ([UUID], DropInsertion) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        // Only our own rows reorder the list; text dragged in from other apps is ignored.
        dragState.isDragging
    }

    func dropEntered(info: DropInfo) {
        guard dragState.isDragging else { return }
        updateInsertion(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard dragState.isDragging else {
            return DropProposal(operation: .cancel)
        }
        updateInsertion(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        switch dragState.dropInsertion {
        case .before(let id, let sid) where (id == item.id || id == nextItemID) && sid == sectionID:
            dragState.dropInsertion = nil
        case .end(let sid) where sid == sectionID && nextItemID == nil:
            dragState.dropInsertion = nil
        default:
            break
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let ids = Array(dragState.draggingIDs)
        guard !ids.isEmpty else {
            dragState.clear()
            return false
        }
        let target = insertion(for: info)
        dragState.dropInsertion = nil
        onDrop(ids, target)
        return true
    }

    private func updateInsertion(info: DropInfo) {
        guard dragState.isDragging else {
            dragState.dropInsertion = nil
            return
        }
        let next = insertion(for: info)
        guard dragState.dropInsertion != next else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            dragState.dropInsertion = next
        }
    }

    private func insertion(for info: DropInfo) -> DropInsertion {
        // Prefer after when pointer is in the lower half of the card.
        if info.location.y < 36 {
            return .before(itemID: item.id, sectionID: sectionID)
        }
        if let nextItemID {
            return .before(itemID: nextItemID, sectionID: sectionID)
        }
        return .end(sectionID: sectionID)
    }
}

private struct SectionEndDropDelegate: DropDelegate {
    let sectionID: UUID
    let dragState: ListDragState
    let onDrop: @MainActor ([UUID], DropInsertion) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragState.isDragging
    }

    func dropEntered(info: DropInfo) {
        guard dragState.isDragging else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            dragState.dropInsertion = .end(sectionID: sectionID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard dragState.isDragging else {
            return DropProposal(operation: .cancel)
        }
        if dragState.dropInsertion != .end(sectionID: sectionID) {
            withAnimation(.easeOut(duration: 0.12)) {
                dragState.dropInsertion = .end(sectionID: sectionID)
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dragState.dropInsertion == .end(sectionID: sectionID) {
            dragState.dropInsertion = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let ids = Array(dragState.draggingIDs)
        dragState.dropInsertion = nil
        guard !ids.isEmpty else {
            dragState.clear()
            return false
        }
        onDrop(ids, .end(sectionID: sectionID))
        return true
    }
}

/// Markdown parsing is not cheap and rows re-render on every selection / drag change,
/// so parsed results are memoised by body text.
@MainActor
private enum MarkdownRenderCache {
    private static var cache: [String: AttributedString] = [:]
    private static var insertionOrder: [String] = []
    private static let limit = 512

    static func attributed(for text: String) -> AttributedString {
        if let hit = cache[text] { return hit }

        let parsed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)

        cache[text] = parsed
        insertionOrder.append(text)
        if insertionOrder.count > limit {
            let evicted = insertionOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return parsed
    }
}

struct MarkdownBody: View {
    let text: String
    var isDone: Bool = false
    var lineLimit: Int? = nil

    var body: some View {
        Text(MarkdownRenderCache.attributed(for: text))
        .font(.system(size: 13))
        .strikethrough(isDone)
        .foregroundStyle(isDone ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .lineSpacing(2)
        .lineLimit(lineLimit)
        .truncationMode(.tail)
        // Intentionally no textSelection — it steals clicks from multi-select.
    }
}
