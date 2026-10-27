import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

struct ExportSummaryView: View {
    let reports: [BookExportService.ExportReport]
    let failedCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    var body: some View {
        NavigationView {
            List {
                ForEach(reports, id: \.url) { report in
                    Section(header: Text(report.url.lastPathComponent)) {
                        Text("已导出 \(report.includedChapters) 章 · 缺少 \(report.missingChapters.count) 章 · 缺少 \(report.missingImages.count) 张图片")
                        ForEach(Array(report.missingChapters.prefix(20).enumerated()), id: \.offset) { _, chapter in
                            Text("未缓存：\(chapter.title)").font(.caption).foregroundColor(.secondary)
                        }
                        if report.missingChapters.count > 20 { Text("其余缺章见目录与缓存列表").font(.caption) }
                    }
                }
                if failedCount > 0 { Text("另有 \(failedCount) 本未能导出，原因见日志。").foregroundColor(.secondary) }
                Text("导出只包含现有离线内容；未缓存章节和不可用插图不会自动下载。EPUB 可打包现有 PNG / JPEG / GIF 资源。").font(.caption).foregroundColor(.secondary)
                Button("分享导出文件") { showShare = true }
            }
            .navigationTitle("导出结果")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showShare) { ActivityShareSheet(items: reports.map(\.url)) }
        }
    }
}
