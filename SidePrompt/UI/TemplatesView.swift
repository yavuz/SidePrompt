import SwiftUI

struct TemplatesSheet: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingTemplate: PromptTemplate?
    @State private var fillingTemplate: PromptTemplate?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Templates")
                    .font(.headline)
                Spacer()
                Button {
                    isCreating = true
                    editingTemplate = PromptTemplate(title: "New template", body: "Write about {{topic}}.")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if store.sortedTemplates.isEmpty {
                ContentUnavailableView(
                    "No templates",
                    systemImage: "doc.text",
                    description: Text("Create a prompt with {{variables}} and reuse it.")
                )
            } else {
                List {
                    ForEach(store.sortedTemplates) { template in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(template.preview)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if !template.variables.isEmpty {
                                    Text(template.variables.map { "{{\($0)}}" }.joined(separator: "  "))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button("Use") {
                                fillingTemplate = template
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Use") { fillingTemplate = template }
                            Button("Edit") { editingTemplate = template }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.deleteTemplate(id: template.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 420, height: 460)
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(template: template, isNew: isCreating) { saved in
                if isCreating {
                    _ = store.addTemplate(title: saved.title, body: saved.body)
                } else {
                    store.updateTemplate(saved)
                }
                isCreating = false
                editingTemplate = nil
            } onCancel: {
                isCreating = false
                editingTemplate = nil
            }
        }
        .sheet(item: $fillingTemplate) { template in
            TemplateFillView(template: template) { values in
                if store.insertFromTemplate(template, values: values) != nil {
                    appModel.showToast("Added from template")
                }
                fillingTemplate = nil
                dismiss()
            } onCancel: {
                fillingTemplate = nil
            }
        }
    }
}

struct TemplateEditorView: View {
    @State var template: PromptTemplate
    let isNew: Bool
    let onSave: (PromptTemplate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Template" : "Edit Template")
                .font(.headline)
            TextField("Title", text: $template.title)
                .textFieldStyle(.roundedBorder)
            Text("Use {{variable}} placeholders in the body.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $template.body)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 160)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
            if !template.variables.isEmpty {
                Text("Variables: " + template.variables.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(template)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 440, height: 360)
    }
}

struct TemplateFillView: View {
    let template: PromptTemplate
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(template.title)
                .font(.headline)
            Text("Fill variables, then add to Inbox.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if template.variables.isEmpty {
                Text("No variables in this template.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(template.variables, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(name, text: binding(for: name), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                    }
                }
            }

            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(preview)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add to Inbox") {
                    onSubmit(values)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding()
        .frame(width: 420, height: 420)
        .onAppear {
            for name in template.variables where values[name] == nil {
                values[name] = ""
            }
        }
    }

    private var preview: String {
        TemplateEngine.render(template.body, values: values)
    }

    private var canSubmit: Bool {
        template.variables.allSatisfy { name in
            !(values[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } || template.variables.isEmpty
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }
}
