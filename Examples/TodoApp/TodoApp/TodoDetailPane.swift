import SwiftUI

import TodoKit

/// One to-do, observed by identifier.
///
/// Completing it here writes and stops. The row this view shows, the row in
/// the list, and the sidebar counts are three separate observations of the
/// same commit, so all three update without anything asking them to.
struct TodoDetailPane: View {

    let database: TodoDatabase
    let todoID: TodoUUID

    @State private var model: TodoDetailModel?
    @State private var failure: String?

    @State private var title = ""
    @State private var notes = ""
    @State private var priority = TodoPriority.normal
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isEditing = false

    var body: some View {
        Group {
            if let model, let todo = model.todo.row {
                form(model: model, todo: todo)
            }
            else if let failure {
                ContentUnavailableView(
                    "Could not open the to-do",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            }
            else if model?.todo.isLoading == false {
                ContentUnavailableView(
                    "This to-do is gone",
                    systemImage: "trash"
                )
            }
            else {
                ProgressView()
            }
        }
        .onAppear(perform: start)
        .onDisappear { model?.stop() }
    }

    private func start() {
        guard model == nil else {
            return
        }
        do {
            model = try TodoDetailModel(database: database, todoID: todoID)
        }
        catch {
            failure = String(describing: error)
        }
    }

    @ViewBuilder
    private func form(model: TodoDetailModel, todo: Todo) -> some View {
        Form {
            Section {
                if isEditing {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                else {
                    Text(todo.title)
                        .font(.headline)
                    if !todo.notes.isEmpty {
                        Text(todo.notes)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Due") {
                if isEditing {
                    Toggle("Has a due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate)
                    }
                }
                else {
                    Text(
                        todo.dueAt.map {
                            $0.wrappedValue.formatted(date: .abbreviated, time: .shortened)
                        } ?? "No due date"
                    )
                }
            }

            Section("Priority") {
                if isEditing {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(TodoPriority.low)
                        Text("Normal").tag(TodoPriority.normal)
                        Text("High").tag(TodoPriority.high)
                    }
                    .pickerStyle(.segmented)
                }
                else {
                    Text(name(of: todo.priority))
                }
            }

            if !model.tags.isEmpty {
                Section("Tags") {
                    Text(model.tags.map(\.name).joined(separator: " · "))
                }
            }

            Section {
                Toggle(
                    "Completed",
                    isOn: Binding(
                        get: { todo.isCompleted },
                        set: { _ = try? database.setCompleted($0, todoID: todo.id) }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(todo.title)
        .toolbar {
            ToolbarItem {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        save(todo)
                    }
                    else {
                        load(todo)
                    }
                    isEditing.toggle()
                }
            }
        }
    }

    private func load(_ todo: Todo) {
        title = todo.title
        notes = todo.notes
        priority = todo.priority
        hasDueDate = todo.dueAt != nil
        dueDate = todo.dueAt?.wrappedValue ?? Date()
    }

    private func save(_ todo: Todo) {
        _ = try? database.updateTodo(
            id: todo.id,
            title: title,
            notes: notes,
            dueAt: hasDueDate ? TodoDate(dueDate) : nil,
            priority: priority
        )
    }

    private func name(of priority: TodoPriority) -> String {
        switch priority {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}
