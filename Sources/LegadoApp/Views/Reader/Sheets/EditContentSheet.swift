import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// 编辑内容 — 修改当前章节的标题与正文文本，支持保存、重置与全部复制（对齐 Android `ContentEditDialog`）。
struct EditContentSheet: View {
    let initialTitle: String
    let initialContent: String
    let onSave: (String, String) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var titleText: String
    @State private var contentText: String
    @State private var showResetConfirm = false
    @State private var showCopiedAlert = false

    init(
        title: String,
        content: String,
        onSave: @escaping (String, String) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.initialTitle = title
        self.initialContent = content
        self.onSave = onSave
        self.onReset = onReset
        _titleText = State(initialValue: title)
        _contentText = State(initialValue: content)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chapter Title input
                VStack(alignment: .leading, spacing: 6) {
                    Text("章节标题")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("章节标题", text: $titleText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                // Chapter Content editor
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("正文内容")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(contentText.count) 字")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    TextEditor(text: $contentText)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("编辑内容")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Menu {
                            Button {
                                copyToClipboard("\(titleText)\n\n\(contentText)")
                                showCopiedAlert = true
                            } label: {
                                Label("复制全部", systemImage: "doc.on.doc")
                            }

                            Button(role: .destructive) {
                                showResetConfirm = true
                            } label: {
                                Label("重置为原始内容", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Button("保存") {
                            let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(trimmedTitle.isEmpty ? initialTitle : trimmedTitle, contentText)
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .alert("确认重置？", isPresented: $showResetConfirm) {
                Button("重置", role: .destructive) {
                    onReset()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除此章节的本地编辑修改，恢复为书源抓取的原始文本。")
            }
            .alert("已复制到剪贴板", isPresented: $showCopiedAlert) {
                Button("确定", role: .cancel) {}
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
