import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// Nine zones, fourteen actions — the same table as Android's `ReadView.click(action)`.
struct TapZoneEditorPanel: View {
    @ObservedObject var config: ReaderConfig

    private let zoneNames = ["左上", "上中", "右上", "左中", "正中", "右中", "左下", "下中", "右下"]

    var body: some View {
        List {
            Section(header: Text("轻点正文区域执行的动作")) {
                ForEach(0..<9, id: \.self) { index in
                    Menu {
                        ForEach(ClickActionCode.allCases, id: \.rawValue) { action in
                            Button(action.label) { config.setClickAction(index, to: action) }
                        }
                    } label: {
                        HStack {
                            Text(zoneNames[index])
                            Spacer()
                            Text(ClickActionCode.from(config.prefs.clickActions[safe: index] ?? 0).label)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }

            Section(footer: Text("至少保留一个「菜单」区域，否则正文将无法再呼出菜单。系统会自动把正中改回菜单。")) {
                Button("恢复默认", action: config.resetClickActions)
            }
        }
        .navigationTitle("点击区域")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
