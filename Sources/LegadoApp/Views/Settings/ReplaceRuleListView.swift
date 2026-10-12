import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// 替换净化 rule library. Mirrors Android's `ReplaceRuleActivity`: enable switch, group
/// label, reorder, add, delete, import/export of the Android `replaceRule.json` array.
public struct ReplaceRuleListView: View {
    @ObservedObject var bookStore = BookStore.shared

    @State private var editingRule: ReplaceRule?
    @State private var showEditor = false
    @State private var showImportSheet = false
    @State private var importText = ""
    @State private var statusMessage: String?
    @State private var showStatus = false
    @State private var confirmDelete: ReplaceRule?

    public init() {}

    public var body: some View {
        List {
            if bookStore.replaceRules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有替换净化规则")
                        .font(.headline)
                    Text("规则会在阅读时按顺序逐条应用，用于去除广告、站点尾巴和乱码。可以从 Android 端导出的 replaceRule.json 直接导入。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            ForEach(bookStore.replaceRules) { rule in
                ruleRow(rule)
            }
            .onDelete { offsets in
                for index in offsets {
                    bookStore.deleteReplaceRule(id: bookStore.replaceRules[index].id)
                }
            }
            .onMove { source, destination in
                bookStore.moveReplaceRule(from: source, to: destination)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("替换净化")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        startNewRule()
                    } label: { Label("添加规则", systemImage: "plus") }

                    Button {
                        showImportSheet = true
                    } label: { Label("粘贴导入", systemImage: "doc.on.clipboard") }

                    Button {
                        exportRules()
                    } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let rule = editingRule {
                ReplaceRuleEditorView(rule: rule) { saved in
                    bookStore.upsertReplaceRule(saved)
                    showEditor = false
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            importSheet
        }
        .alert("提示", isPresented: $showStatus) {
            Button("好", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
        .confirmationDialog(confirmDelete.map { "删除「\($0.name)」？" } ?? "确认删除该规则？",
                            isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        ), actions: {
            Button("删除", role: .destructive) {
                if let rule = confirmDelete { bookStore.deleteReplaceRule(id: rule.id) }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        })
    }

    private func ruleRow(_ rule: ReplaceRule) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { bookStore.setReplaceRule(rule.id, enabled: $0) }
            ))
            .labelsHidden()

            Button {
                editingRule = rule
                showEditor = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        if let group = rule.group, !group.isEmpty {
                            Text(group)
                        }
                        Text(rule.isRegex ? "正则" : "字面")
                        if !rule.isValid { Text("规则无效").foregroundColor(.red) }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                confirmDelete = rule
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private var importSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("粘贴 Android 导出的 replaceRule.json")) {
                    TextEditor(text: $importText)
                        .frame(minHeight: 220)
                        .font(.system(.caption, design: .monospaced))
                }
                Button("导入") {
                    let added = bookStore.importReplaceRules(json: importText)
                    importText = ""
                    showImportSheet = false
                    notify(added > 0 ? "已导入 \(added) 条新规则" : "未识别到有效规则")
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("导入规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showImportSheet = false }
                }
            }
        }
    }

    private func notify(_ message: String) {
        statusMessage = message
        showStatus = true
    }

    private func startNewRule() {
        editingRule = ReplaceRule(id: Int64(Date().timeIntervalSince1970 * 1000),
                                  order: (bookStore.replaceRules.map { $0.order }.max() ?? -1) + 1)
        showEditor = true
    }

    private func exportRules() {
        guard let json = bookStore.exportReplaceRulesJSON() else {
            notify("没有可导出的规则")
            return
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("replaceRule.json")
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
            notify("已导出到 \(url.lastPathComponent)，可在「文件」App 中取出")
        } catch {
            notify("导出失败：\(error.localizedDescription)")
        }
    }
}

/// Single-rule editor. Field set matches Android's `activity_replace_edit.xml`.
public struct ReplaceRuleEditorView: View {
    @State var rule: ReplaceRule
    let onSave: (ReplaceRule) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(rule: ReplaceRule, onSave: @escaping (ReplaceRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本")) {
                    TextField("规则名称", text: $rule.name)
                    TextField("分组（可选）", text: Binding(
                        get: { rule.group ?? "" },
                        set: { rule.group = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section(header: Text("替换")) {
                    TextField("替换内容（正则或字面）", text: $rule.pattern)
                        .disableAutocorrection(true)
                    TextField("替换为", text: $rule.replacement)
                        .disableAutocorrection(true)

                    Toggle("正则替换", isOn: $rule.isRegex)
                    Toggle("作用于标题", isOn: $rule.scopeTitle)
                    Toggle("作用于正文", isOn: $rule.scopeContent)
                }

                Section(header: Text("范围与超时")) {
                    TextField("替换范围（书名或书源 URL，留空为全部）", text: Binding(
                        get: { rule.scope ?? "" },
                        set: { rule.scope = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("排除范围", text: Binding(
                        get: { rule.excludeScope ?? "" },
                        set: { rule.excludeScope = $0.isEmpty ? nil : $0 }
                    ))

                    Stepper(value: $rule.timeoutMillisecond, in: 0...30000, step: 500) {
                        HStack {
                            Text("超时时间")
                            Spacer()
                            Text(rule.timeoutMillisecond == 0
                                 ? "默认 3000 ms"
                                 : "\(rule.timeoutMillisecond) ms")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !rule.pattern.isEmpty, !rule.isValid {
                    Section {
                        Text("表达式无法编译，或结尾是未转义的 |。保存后不会生效。")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("说明")) {
                    Text("超时的规则会被自动停用，避免一个写坏的正则拖慢整本书。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("替换规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
