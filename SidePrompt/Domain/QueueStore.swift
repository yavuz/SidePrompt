import Foundation
import Observation

@MainActor
@Observable
final class QueueStore {
    private(set) var sections: [SectionModel] = []
    private(set) var items: [PromptItem] = []
    private(set) var templates: [PromptTemplate] = []
    private(set) var lastError: String?

    var searchQuery: String = ""
    var selectedItemIDs: Set<UUID> = []
    /// Anchor for Shift-click range selection.
    var selectionAnchorID: UUID?
    /// When set, ⌘C should go to the text editor instead of copying list items.
    var editingItemID: UUID?

    func endEditing() {
        guard editingItemID != nil else { return }
        editingItemID = nil
    }

    private let persistence: LocalStore

    init(persistence: LocalStore = LocalStore()) {
        self.persistence = persistence
        load()
    }

    var sortedSections: [SectionModel] {
        sections.sorted { $0.order < $1.order }
    }

    var sortedTemplates: [PromptTemplate] {
        templates.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func items(in section: SectionModel) -> [PromptItem] {
        filteredItems
            .filter { $0.sectionId == section.id }
            .sorted { $0.order < $1.order }
    }

    var filteredItems: [PromptItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.body.localizedCaseInsensitiveContains(query) }
    }

    func load() {
        do {
            let data = try persistence.load()
            sections = data.sections
            items = data.items
            templates = data.templates.isEmpty ? AppStoreData.defaultTemplates : data.templates
            ensureInbox()
            lastError = nil
        } catch {
            let fallback = AppStoreData.empty
            sections = fallback.sections
            items = fallback.items
            templates = fallback.templates
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func capture(_ text: String, kind: ItemKind = .note) -> PromptItem? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        ensureInbox()
        guard let inbox = sections.first(where: { $0.title == "Inbox" }) ?? sections.first else {
            return nil
        }
        let order = (items.filter { $0.sectionId == inbox.id }.map(\.order).max() ?? -1) + 1
        let item = PromptItem(sectionId: inbox.id, body: body, kind: kind, order: order)
        items.append(item)
        save()
        return item
    }

    func addItem(to sectionId: UUID, body: String = "", kind: ItemKind = .prompt) -> PromptItem {
        let order = (items.filter { $0.sectionId == sectionId }.map(\.order).max() ?? -1) + 1
        let item = PromptItem(sectionId: sectionId, body: body, kind: kind, order: order)
        items.append(item)
        selectedItemIDs = [item.id]
        selectionAnchorID = item.id
        save()
        return item
    }

    func updateBody(id: UUID, body: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].body = body
        items[index].updatedAt = Date()
        save()
    }

    func toggleDone(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        items[index].updatedAt = Date()
        save()
    }

    func delete(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        selectedItemIDs.subtract(ids)
        save()
    }

    func addSection(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let order = (sections.map(\.order).max() ?? -1) + 1
        sections.append(SectionModel(title: trimmed, order: order))
        save()
    }

    func renameSection(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[index].title = trimmed
        save()
    }

    /// Whether a section can be removed (Inbox and the last section are protected).
    func canDeleteSection(id: UUID) -> Bool {
        guard sections.count > 1,
              let section = sections.first(where: { $0.id == id }) else { return false }
        return section.title != "Inbox"
    }

    /// Deletes a section. Items are moved to Inbox. Returns moved item count, or nil if refused.
    @discardableResult
    func deleteSection(id: UUID) -> Int? {
        guard canDeleteSection(id: id) else { return nil }
        ensureInbox()
        guard let inbox = sections.first(where: { $0.title == "Inbox" }),
              inbox.id != id else { return nil }

        let movingIDs = items.filter { $0.sectionId == id }.map(\.id)
        if !movingIDs.isEmpty {
            moveItems(movingIDs, to: inbox.id, before: nil)
        }

        sections.removeAll { $0.id == id }
        for (order, section) in sortedSections.enumerated() {
            guard let index = sections.firstIndex(where: { $0.id == section.id }) else { continue }
            sections[index].order = order
        }
        save()
        return movingIDs.count
    }

    func moveItem(_ itemId: UUID, to sectionId: UUID) {
        moveItems([itemId], to: sectionId, before: nil)
    }

    /// Moves items into `sectionId`. If `before` is set, inserts ahead of that item
    /// (must already be in the target section, or the move appends).
    func moveItems(_ ids: [UUID], to sectionId: UUID, before beforeId: UUID? = nil) {
        let uniqueIDs = orderedIDs(from: ids)
        guard !uniqueIDs.isEmpty, sections.contains(where: { $0.id == sectionId }) else { return }

        let moving = uniqueIDs.compactMap { id in items.first(where: { $0.id == id }) }
        guard !moving.isEmpty else { return }

        var destination = items
            .filter { $0.sectionId == sectionId && !uniqueIDs.contains($0.id) }
            .sorted { $0.order < $1.order }

        if let beforeId,
           !uniqueIDs.contains(beforeId),
           let insertAt = destination.firstIndex(where: { $0.id == beforeId }) {
            destination.insert(contentsOf: moving, at: insertAt)
        } else {
            destination.append(contentsOf: moving)
        }

        let now = Date()
        for (order, item) in destination.enumerated() {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
            items[index].sectionId = sectionId
            items[index].order = order
            items[index].updatedAt = now
        }

        // Compact orders in any section that still holds leftovers.
        for section in sections {
            renumber(sectionId: section.id)
        }

        selectedItemIDs = Set(uniqueIDs)
        selectionAnchorID = uniqueIDs.first
        editingItemID = nil
        save()
    }

    /// Display order of the given IDs (section order, then item order).
    func orderedIDs(from ids: [UUID]) -> [UUID] {
        let wanted = Set(ids)
        return displayOrderedItems()
            .map(\.id)
            .filter { wanted.contains($0) }
    }

    private func renumber(sectionId: UUID) {
        let ordered = items
            .filter { $0.sectionId == sectionId }
            .sorted { $0.order < $1.order }
        for (order, item) in ordered.enumerated() where item.order != order {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
            items[index].order = order
        }
    }

    func copySelectedAsList() -> String {
        let selected = items
            .filter { selectedItemIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.sectionId == rhs.sectionId {
                    return lhs.order < rhs.order
                }
                let leftSection = sections.first(where: { $0.id == lhs.sectionId })?.order ?? 0
                let rightSection = sections.first(where: { $0.id == rhs.sectionId })?.order ?? 0
                return leftSection < rightSection
            }
        let source = selected.isEmpty
            ? filteredItems.filter { !$0.isDone }.sorted { $0.order < $1.order }
            : selected
        return source
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Copies only explicitly selected items (⌘C). Returns nil if nothing is selected.
    func copySelectedItems() -> String? {
        guard !selectedItemIDs.isEmpty else { return nil }
        let text = orderedSelectedBodies().joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    @discardableResult
    func mergeSelected() -> PromptItem? {
        let selected = orderedSelectedItems()
        guard selected.count >= 2, let first = selected.first else { return nil }
        let mergedBody = selected
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let removeIDs = Set(selected.dropFirst().map(\.id))
        guard let index = items.firstIndex(where: { $0.id == first.id }) else { return nil }
        items[index].body = mergedBody
        items[index].updatedAt = Date()
        items[index].isDone = false
        items.removeAll { removeIDs.contains($0.id) }
        selectedItemIDs = [first.id]
        editingItemID = nil
        save()
        return items[index]
    }

    func selectAllFiltered() {
        selectedItemIDs = Set(filteredItems.map(\.id))
        selectionAnchorID = filteredItems.sorted(by: { $0.order < $1.order }).first?.id
        editingItemID = nil
    }

    func toggleSelection(id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
        selectionAnchorID = id
        if editingItemID == id {
            editingItemID = nil
        }
    }

    func selectRange(from startID: UUID, to endID: UUID) {
        endEditing()
        let ordered = displayOrderedItems()
        guard let start = ordered.firstIndex(where: { $0.id == startID }),
              let end = ordered.firstIndex(where: { $0.id == endID }) else {
            selectedItemIDs = [endID]
            selectionAnchorID = endID
            return
        }
        let lower = min(start, end)
        let upper = max(start, end)
        selectedItemIDs = Set(ordered[lower...upper].map(\.id))
    }

    private func displayOrderedItems() -> [PromptItem] {
        sortedSections.flatMap { section in
            items(in: section)
        }
    }

    private func orderedSelectedItems() -> [PromptItem] {
        items
            .filter { selectedItemIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.sectionId == rhs.sectionId {
                    return lhs.order < rhs.order
                }
                let leftSection = sections.first(where: { $0.id == lhs.sectionId })?.order ?? 0
                let rightSection = sections.first(where: { $0.id == rhs.sectionId })?.order ?? 0
                return leftSection < rightSection
            }
    }

    private func orderedSelectedBodies() -> [String] {
        orderedSelectedItems()
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func copyBodies(for ids: Set<UUID>) -> String {
        items
            .filter { ids.contains($0.id) }
            .sorted { $0.order < $1.order }
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Templates

    @discardableResult
    func addTemplate(title: String, body: String) -> PromptTemplate {
        let template = PromptTemplate(title: title, body: body)
        templates.append(template)
        save()
        return template
    }

    func updateTemplate(_ template: PromptTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        var updated = template
        updated.updatedAt = Date()
        templates[index] = updated
        save()
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func insertFromTemplate(
        _ template: PromptTemplate,
        values: [String: String],
        sectionId: UUID? = nil
    ) -> PromptItem? {
        let targetSection = sectionId
            ?? sections.first(where: { $0.title == "Inbox" })?.id
            ?? sections.first?.id
        guard let targetSection else { return nil }
        let body = TemplateEngine.render(template.body, values: values)
        return addItem(to: targetSection, body: body, kind: .prompt)
    }

    func saveSelectedAsTemplate(title: String) -> PromptTemplate? {
        guard let text = copySelectedItems() else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        return addTemplate(title: trimmedTitle, body: text)
    }

    private func ensureInbox() {
        if sections.isEmpty {
            sections = [SectionModel(title: "Inbox", order: 0)]
            save()
        }
    }

    private func save() {
        do {
            try persistence.save(AppStoreData(sections: sections, items: items, templates: templates))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
