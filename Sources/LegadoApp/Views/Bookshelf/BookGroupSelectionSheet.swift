import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

struct BookGroupSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = BookStore.shared
    let bookURLs: Set<String>
    var onSaved: (() -> Void)?
    @State private var mask: Int64 = 0

    private var groups: [BookGroup] { BookGroupStore.load().filter { $0.groupId > 0 }.sorted { $0.order < $1.order } }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(groups) { group in
                        Toggle(group.groupName, isOn: Binding(
                            get: { mask & group.groupId != 0 },
                            set: { checked in
                                if checked { mask |= group.groupId } else { mask &= ~group.groupId }
                            }))
                    }
                    if groups.isEmpty { Text("请先在分组管理中添加分组").foregroundColor(.secondary) }
                } footer: {
                    Text(bookURLs.count > 1 ? "所有选中书籍将使用以上分组；全部取消表示未分组。" : "可选择多个分组；全部取消表示未分组。")
                }
                if let issue = store.groupMigrationIssue { Text(issue).foregroundColor(.secondary) }
            }
            .navigationTitle("设置分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.moveBooks(bookUrls: bookURLs, toGroupId: mask); onSaved?(); dismiss() }
                        .disabled(!store.usesGroupBitmasks)
                }
            }
            .onAppear {
                let selected = store.bookshelf.filter { bookURLs.contains($0.bookUrl) }
                mask = selected.dropFirst().reduce(max(0, selected.first?.group ?? 0)) { $0 & max(0, $1.group) }
            }
        }
    }
}

struct BookGroupNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = BookStore.shared
    let group: BookGroup
    @State private var name: String
    @State private var enableRefresh: Bool
    @State private var error: String?

    init(group: BookGroup) {
        self.group = group
        _name = State(initialValue: group.groupName)
        _enableRefresh = State(initialValue: group.enableRefresh)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("分组名称", text: $name)
                Toggle("允许下拉更新", isOn: $enableRefresh)
                if let error = error { Text(error).foregroundColor(.red) }
            }
            .navigationTitle(group.groupId == 0 ? "新建分组" : "重命名分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            if group.groupId == 0 { _ = try store.addBookGroup(name: name, enableRefresh: enableRefresh) }
                            else { store.renameBookGroup(id: group.groupId, name: name, enableRefresh: enableRefresh) }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
