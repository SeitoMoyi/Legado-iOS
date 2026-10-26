import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

struct RuleLinkImportView: View {
    let link: String
    @Environment(\.dismiss) private var dismiss
    @State private var json: String?
    @State private var error: String?
    @State private var attempt = 0
    var body: some View {
        Group {
            if let json = json { ScanResultSheet(raw: json) }
            else {
                NavigationView {
                    VStack(spacing: 12) {
                        if let error = error { Text(error); Button("重试") { attempt += 1 } }
                        else { ProgressView("正在下载规则…") }
                    }.padding()
                    .navigationTitle("导入规则")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                }
            }
        }
        .task(id: attempt) {
            error = nil
            do { let value = try await RuleLinkService.fetch(link); try Task.checkCancellation(); json = value }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct RuleLinkIntent: Identifiable {
    let id = UUID()
    let link: String
}
