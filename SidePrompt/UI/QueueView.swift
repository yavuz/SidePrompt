import AppKit
import SwiftUI

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
                        store.endEditing()
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
        ScrollView {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.endEditing()
                    }

                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(store.sortedSections) { section in
                        sectionBlock(section)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
        }
    }

    private func sectionBlock(_ section: SectionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.7)
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.endEditing()
            }

            let sectionItems = store.items(in: section)
            if sectionItems.isEmpty {
                Text("No items")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(sectionItems) { item in
                        ItemRow(item: item)
                    }
                }
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
    let item: PromptItem
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private var isEditing: Bool {
        store.editingItemID == item.id
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
                    MarkdownBody(text: item.body, isDone: item.isDone)
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
        .onTapGesture {
            handleTap()
        }
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
            Button(isSelected ? "Deselect" : "Select") {
                store.endEditing()
                store.toggleSelection(id: item.id)
            }
            Button("Copy") {
                if PasteboardService.copy(item.body) {
                    appModel.showToast("Copied")
                }
            }
            Button(item.isDone ? "Mark Incomplete" : "Mark Done") {
                store.toggleDone(id: item.id)
            }
            Button("Edit") { beginEdit() }
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
        let raw = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
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

        beginEdit()
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

struct MarkdownBody: View {
    let text: String
    var isDone: Bool = false

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(.system(size: 13))
        .strikethrough(isDone)
        .foregroundStyle(isDone ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .lineSpacing(2)
        // Intentionally no textSelection — it steals clicks from multi-select.
    }
}
