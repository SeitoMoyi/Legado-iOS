import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AppLogView: View {
    @State private var entries = AppLogStore.shared.snapshot()
    var body: some View {
        List {
            if entries.isEmpty { Text("本次运行暂无日志").foregroundColor(.secondary) }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(entry.category) · \(entry.time.formatted(date: .omitted, time: .standard))").font(.caption).foregroundColor(.secondary)
                    Text(entry.message).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("日志")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("拷贝") {
                    let text = entries.map { "\($0.time) [\($0.category)] \($0.message)" }.joined(separator: "\n")
                    #if canImport(UIKit)
                    UIPasteboard.general.string = text
                    #elseif canImport(AppKit)
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    #endif
                }
                Button("清空") { AppLogStore.shared.clear() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppLogStore.didChange).receive(on: DispatchQueue.main)) { _ in entries = AppLogStore.shared.snapshot() }
    }
}
