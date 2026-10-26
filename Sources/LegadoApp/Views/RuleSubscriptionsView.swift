import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

struct RuleSubscriptionsView: View {
    @State private var subscriptions = RuleSubStore.load()
    @State private var edited: RuleSub?
    @State private var preview: RuleSubscriptionPreview?
    @State private var selected = Set<Int>()
    @State private var replacingExisting = false
    @State private var fetchingID: Int64?
    @State private var previewID: Int64?
    @State private var fetchTask: Task<Void, Never>?
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        List {
            Section(footer: Text("打开订阅后预览并选择要导入的规则。默认保留本地已有规则，可在预览中选择替换。")) {
                ForEach(subscriptions) { item in
                    HStack {
                        Button { fetch(item) } label: {
                            VStack(alignment: .leading) {
                                Text(item.name.isEmpty ? item.url : item.name)
                                Text(typeName(item.type)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if fetchingID == item.id { ProgressView() }
                        Button { edited = item } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    if offsets.contains(where: { subscriptions[$0].id == fetchingID }) { fetchTask?.cancel(); fetchingID = nil }
                    subscriptions.remove(atOffsets: offsets)
                    RuleSubStore.save(subscriptions)
                }
                .onMove { from, to in
                    subscriptions.move(fromOffsets: from, toOffset: to)
                    for index in subscriptions.indices { subscriptions[index].customOrder = index }
                    RuleSubStore.save(subscriptions)
                }
            }
        }
        .navigationTitle("规则订阅")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS)
                EditButton()
                #endif
                Button { edited = RuleSub() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $edited) { item in
            RuleSubscriptionEditor(value: item) { value in
                subscriptions = try RuleSubStore.upsert(value, into: subscriptions)
                RuleSubStore.save(subscriptions)
            }
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            NavigationView {
                List {
                    Toggle("替换本地已有规则", isOn: $replacingExisting)
                    if let preview = preview {
                        ForEach(Array(preview.names.enumerated()), id: \.offset) { index, name in
                            Button {
                                if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                            } label: {
                                HStack { Text(name); Spacer(); if selected.contains(index) { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                }
                .navigationTitle("导入预览")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { preview = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入 (\(selected.count))") { applyPreview() }.disabled(selected.isEmpty)
                    }
                }
            }
        }
        .alert("规则订阅", isPresented: $showMessage) { Button("确定", role: .cancel) {} } message: { Text(message) }
        .onDisappear { fetchTask?.cancel(); fetchTask = nil; fetchingID = nil }
    }

    private func typeName(_ type: Int) -> String { [0: "书源", 1: "订阅源", 2: "替换净化"][type] ?? "未知类型 (\(type))" }

    private func fetch(_ item: RuleSub) {
        fetchTask?.cancel()
        fetchingID = item.id
        fetchTask = Task { @MainActor in
            do {
                let result = try await RuleSubscriptionService().fetch(item)
                try Task.checkCancellation()
                preview = result
                previewID = item.id
                selected = Set(result.names.indices)
                replacingExisting = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { message = error.localizedDescription; showMessage = true } }
            if !Task.isCancelled { fetchingID = nil }
        }
    }

    private func applyPreview() {
        guard let preview = preview else { return }
        let filtered: RuleSubscriptionPreview
        switch preview {
        case .bookSources(let list): filtered = .bookSources(list.enumerated().filter { selected.contains($0.offset) }.map(\.element))
        case .rssSources(let list): filtered = .rssSources(list.enumerated().filter { selected.contains($0.offset) }.map(\.element))
        case .replaceRules(let list): filtered = .replaceRules(list.enumerated().filter { selected.contains($0.offset) }.map(\.element))
        }
        let count = BookStore.shared.importSubscription(filtered, replacingExisting: replacingExisting)
        if let id = previewID, let index = subscriptions.firstIndex(where: { $0.id == id }) {
            subscriptions[index].update = Int64(Date().timeIntervalSince1970 * 1000)
            RuleSubStore.save(subscriptions)
        }
        self.preview = nil
        message = "已导入 \(count) 条规则"
        showMessage = true
    }
}

private struct RuleSubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: RuleSub
    var save: (RuleSub) throws -> Void
    @State private var error = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("名称", text: $value.name)
                TextField("订阅地址", text: $value.url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                Picker("类型", selection: $value.type) {
                    Text("书源").tag(0); Text("订阅源").tag(1); Text("替换净化").tag(2)
                    if !(0...2).contains(value.type) { Text("未知类型 (\(value.type))").tag(value.type) }
                }
                if !error.isEmpty { Text(error).foregroundColor(.red) }
            }
            .navigationTitle("编辑订阅")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try save(value); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}
