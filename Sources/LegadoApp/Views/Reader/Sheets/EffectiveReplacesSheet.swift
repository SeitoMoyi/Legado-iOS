import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// 「起效的替换」 — which 净化 rules were in scope for this book, and which of them actually
/// changed the current chapter. Mirrors Android's `EffectiveReplacesDialog`.
///
/// Doubles as the explanation screen for 净化: the word is Android's own term and says nothing
/// to a new reader, so this sheet defines it and gives the switch plus the rule editor.
struct EffectiveReplacesSheet: View {
    let book: Book
    let cacheKey: String
    let enabled: Bool
    let onSetEnabled: (Bool) -> Void

    @ObservedObject var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ReplaceRule?
    @State private var showEditor = false

    private var matching: [ReplaceRule] {
        bookStore.matchingReplaceRules(bookName: book.name, bookOrigin: book.origin)
    }

    private var didChange: Set<Int64> {
        Set(ContentProcessor.shared.result(forKey: cacheKey)?.effectiveRules.map { $0.id } ?? [])
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("净化是什么")) {
                    Toggle("本书启用净化", isOn: Binding(get: { enabled }, set: { onSetEnabled($0) }))
                    Text("净化会按下面的「替换规则」重写正文：删掉与章节标题重复的开头、去掉广告和乱码字符，"
                         + "并按设置做简繁转换与首行缩进。没有规则时开与关都没有效果。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    NavigationLink {
                        ReplaceRuleListView()
                    } label: {
                        Text("替换规则管理（当前共 \(bookStore.replaceRules.count) 条）")
                    }
                }

                Section(header: Text("本章实际生效")) {
                    if didChange.isEmpty {
                        Text(enabled
                             ? "本章没有命中任何规则（正文与原文一致）"
                             : "净化已关闭，正文保持书源原样")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    ForEach(matching.filter { didChange.contains($0.id) }) { rule in
                        ruleRow(rule, effective: true)
                    }
                }

                Section(header: Text("匹配本书的全部规则")) {
                    if matching.isEmpty {
                        Text("当前书名与书源下没有可用规则，可在上面「替换规则管理」里添加或导入")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    ForEach(matching) { rule in
                        ruleRow(rule, effective: didChange.contains(rule.id))
                    }
                }
            }
            .navigationTitle("净化与替换规则")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let rule = editing {
                ReplaceRuleEditorView(rule: rule) { saved in
                    bookStore.upsertReplaceRule(saved)
                    showEditor = false
                }
            }
        }
    }

    private func ruleRow(_ rule: ReplaceRule, effective: Bool) -> some View {
        Button {
            editing = rule
            showEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: effective ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(effective ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                        .foregroundColor(.primary)
                    Text(rule.pattern)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !rule.isEnabled {
                    Text("已停用")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}
