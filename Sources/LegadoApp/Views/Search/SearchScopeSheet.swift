import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Picks which sources a search runs against: everything, a set of groups, or one source.
/// Same three states Android's `SearchScopeDialog` offers, and the choice is persisted in the
/// Android-compatible `searchScope` string.
struct SearchScopeSheet: View {
    @ObservedObject var viewModel = SearchViewModel.shared
    let onDone: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case group = "分组"
        case source = "书源"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .group
    @State private var selectedGroups: Set<String> = []
    @State private var keyword = ""
    @Environment(\.dismiss) private var dismiss

    private var allGroups: [String] {
        Set(BookStore.shared.sources.flatMap { $0.groups }).sorted(by: <)
    }

    private var filteredSources: [BookSource] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = viewModel.availableSources
        guard !needle.isEmpty else { return sources }
        return sources.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(needle)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button("全部书源（清除当前范围）") {
                        viewModel.scope = .all
                        onDone()
                        dismiss()
                    }
                }

                Section {
                    Picker("范围", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                switch mode {
                case .group:
                    Section(header: Text("分组（可多选）")) {
                        if allGroups.isEmpty {
                            Text("书源还没有配置分组")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        ForEach(allGroups, id: \.self) { group in
                            Toggle(isOn: binding(for: group)) { Text(group) }
                        }
                    }
                case .source:
                    Section(header: Text("书源（单选）")) {
                        ForEach(filteredSources) { source in
                            Button {
                                viewModel.selectSource(url: source.bookSourceUrl)
                                onDone()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.bookSourceName)
                                            .foregroundColor(.primary)
                                        if let group = source.displayGroup, !group.isEmpty {
                                            Text(group)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if viewModel.scope.sourceUrl == source.bookSourceUrl {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $keyword, prompt: "筛选书源")
            .navigationTitle("搜索范围")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        applyGroups()
                        onDone()
                        dismiss()
                    }
                }
            }
            .onAppear { selectedGroups = Set(viewModel.scope.groups) }
        }
    }

    private func binding(for group: String) -> Binding<Bool> {
        Binding(
            get: { selectedGroups.contains(group) },
            set: { isOn in
                if isOn { selectedGroups.insert(group) } else { selectedGroups.remove(group) }
            }
        )
    }

    private func applyGroups() {
        if selectedGroups.isEmpty {
            viewModel.scope = .all
        } else {
            viewModel.scope = SearchScope(raw: selectedGroups.sorted().joined(separator: ","))
        }
    }
}
