import SwiftUI
import CoreImage
#if canImport(LegadoCore)
import LegadoCore
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - QR Code Generation (Plan 第一批 Part 3: 二维码全链路)

public enum QRCodeImageBuilder {

    /// Renders `text` as a QR code bitmap. `scale` controls module size in pixels.
    public static func makeImage(text: String, scale: CGFloat = 10) -> CGImage? {
        guard !text.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

// MARK: - Share-QR View (生成分享二维码)

/// Shows a generated QR for `content` with save/share/copy actions.
public struct QRCodeShareView: View {
    public let content: String
    public let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var savedToAlbum: Bool = false
    @State private var shareItems: [Any]? = nil
    @State private var copied: Bool = false

    public init(content: String, title: String = "分享二维码") {
        self.content = content
        self.title = title
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                if let cg = QRCodeImageBuilder.makeImage(text: content) {
                    #if canImport(UIKit)
                    Image(uiImage: UIImage(cgImage: cg))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
                    #else
                    Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: 240, height: 240)))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                    #endif
                } else {
                    Text("二维码生成失败")
                        .foregroundColor(.secondary)
                }

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 14) {
                    #if os(iOS)
                    Button {
                        saveToAlbum()
                    } label: {
                        Label(savedToAlbum ? "已保存" : "保存到相册", systemImage: savedToAlbum ? "checkmark.circle" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(savedToAlbum)
                    #endif

                    Button {
                        shareItems = [content]
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = content
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                        #endif
                        copied = true
                    } label: {
                        Label(copied ? "已拷贝" : "拷贝内容", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(copied)
                }
                Spacer()
            }
            .navigationTitle("二维码")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )) {
                if let items = shareItems {
                    ActivityShareSheet(items: items)
                }
            }
        }
    }

    #if os(iOS)
    private func saveToAlbum() {
        guard let cg = QRCodeImageBuilder.makeImage(text: content) else { return }
        let image = UIImage(cgImage: cg)
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        withAnimation { savedToAlbum = true }
    }
    #endif
}

// MARK: - Scanner result sheet (shared across platforms)

/// Renders a decoded payload with the matching import actions. Presented both after live
/// scanning (iOS camera) and after album image decoding.
public struct ScanResultSheet: View {
    public let raw: String
    @ObservedObject private var bookStore = BookStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var resultMessage: String? = nil
    @State private var showAddURL: Bool = false

    public init(raw: String) {
        self.raw = raw
    }

    private var payload: ScanPayload { ScanPayload.detect(raw) }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("识别结果")) {
                    Label(payload.kindLabel, systemImage: icon)
                        .font(.headline)
                    Text(raw)
                        .font(.caption.monospaced())
                        .lineLimit(10)
                        .textSelection(.enabled)
                }

                Section {
                    actionButtons
                }

                if let message = resultMessage {
                    Section {
                        Label(message, systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("扫码结果")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddURL) {
                AddUrlSheet(url: raw)
            }
        }
    }

    private var icon: String {
        switch payload {
        case .bookSources: return "books.vertical"
        case .replaceRules: return "wand.and.stars"
        case .rssSources: return "antenna.radiowaves.left.and.right"
        case .dictRules: return "character.book.closed"
        case .webdavConfig: return "icloud"
        case .importURL: return "link"
        case .text: return "doc.text"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch payload {
        case .bookSources(let json):
            Button {
                importSources(json)
            } label: {
                Label("导入书源", systemImage: "square.and.arrow.down")
            }
        case .replaceRules(let json):
            Button {
                let count = bookStore.importReplaceRules(json: json)
                resultMessage = "已导入 \(count) 条替换规则"
            } label: {
                Label("导入替换规则", systemImage: "square.and.arrow.down")
            }
        case .rssSources(let json):
            Button {
                let count = importRssSources(json)
                resultMessage = "已导入 \(count) 个订阅源"
            } label: {
                Label("导入订阅源", systemImage: "square.and.arrow.down")
            }
        case .dictRules(let json):
            Button {
                let count = importDictRules(json)
                resultMessage = "已导入 \(count) 条字典规则"
            } label: {
                Label("导入字典规则", systemImage: "square.and.arrow.down")
            }
        case .webdavConfig(let json):
            Button {
                applyWebDAVConfig(json)
            } label: {
                Label("写入 WebDAV 配置", systemImage: "icloud.and.arrow.down")
            }
        case .importURL:
            if raw.lowercased().hasPrefix("http") {
                Button {
                    dismiss()
                    showAddURL = true
                } label: {
                    Label("按网址添加书籍", systemImage: "book.badge.plus")
                }
            }
            Button {
                copy(raw)
            } label: {
                Label("拷贝链接", systemImage: "doc.on.doc")
            }
        case .text:
            Button {
                copy(raw)
            } label: {
                Label("拷贝内容", systemImage: "doc.on.doc")
            }
        }
    }

    private func importSources(_ json: String) {
        do {
            let count = try bookStore.importSources(json: json)
            resultMessage = "已导入 \(count) 个书源"
        } catch {
            resultMessage = "导入失败: JSON 无法解析为书源"
        }
    }

    /// Accepts either a bare JSON array or one wrapped object.
    private func decodeList<T: Decodable>(_ type: T.Type, from json: String) -> [T]? {
        guard let data = json.data(using: .utf8) else { return nil }
        if let array = try? JSONDecoder().decode([T].self, from: data) { return array }
        if let single = try? JSONDecoder().decode(T.self, from: data) { return [single] }
        return nil
    }

    private func importRssSources(_ json: String) -> Int {
        guard let decoded = decodeList(RssSource.self, from: json) else { return 0 }
        var existing = RssStore.loadSources()
        var added = 0
        for source in decoded {
            if let idx = existing.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) {
                existing[idx] = source
            } else {
                existing.append(source)
                added += 1
            }
        }
        RssStore.saveSources(existing)
        return added
    }

    private func importDictRules(_ json: String) -> Int {
        guard let decoded = decodeList(DictRule.self, from: json) else { return 0 }
        var existing = DictRuleStore.load()
        var added = 0
        for rule in decoded {
            if let idx = existing.firstIndex(where: { $0.name == rule.name }) {
                existing[idx] = rule
            } else {
                existing.append(rule)
                added += 1
            }
        }
        DictRuleStore.save(existing)
        return added
    }

    private func applyWebDAVConfig(_ json: String) {
        guard let data = json.data(using: .utf8),
              var config = try? JSONDecoder().decode(WebDAVConfig.self, from: data),
              !config.url.isEmpty else {
            resultMessage = "WebDAV 配置字段不完整"
            return
        }
        if config.deviceName.isEmpty {
            config.deviceName = WebDAVConfig.defaultDeviceName
        }
        WebDAVService.shared.saveConfig(config)
        resultMessage = "已写入 WebDAV 配置，可到「备份与恢复」验证连接"
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        resultMessage = "已拷贝到剪贴板"
    }
}

#if os(iOS)
import AVFoundation
import PhotosUI

// MARK: - Live Camera Scanner (AVFoundation)

final class QRScanPreviewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)? = nil
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard !isConfigured else { return }
        isConfigured = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.startSession() }
        }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue, !value.isEmpty else { return }
        // Throttle: one camera frame loop can emit many hits for the same code.
        session.stopRunning()
        onCode?(value)
    }

    func resume() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }
}

struct CameraPreviewView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScanPreviewController {
        let controller = QRScanPreviewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: QRScanPreviewController, context: Context) {
        controller.onCode = onCode
    }
}

struct AlbumQRPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: AlbumQRPicker
        init(_ parent: AlbumQRPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { parent.dismiss() }
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [onImage = parent.onImage] object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { onImage(image) }
                }
            }
        }
    }
}

// MARK: - SwiftUI Scanner Sheet

public struct QRScannerSheet: View {
    /// Called for every decoded payload (camera or album image).
    public let onResult: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showAlbumPicker: Bool = false
    @State private var torchOn: Bool = false
    @State private var sessionHint: String? = nil

    public init(onResult: @escaping (String) -> Void) {
        self.onResult = onResult
    }

    public var body: some View {
        NavigationView {
            ZStack {
                CameraPreviewView { code in
                    onResult(code)
                }
                .ignoresSafeArea()

                // Framing hint
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 250, height: 250)
                VStack {
                    Spacer()
                    Text(sessionHint ?? "对准二维码自动识别")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(8)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(8)
                    HStack(spacing: 28) {
                        Button {
                            showAlbumPicker = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 22))
                                Text("相册识别").font(.caption2)
                            }
                            .foregroundColor(.white)
                        }
                        Button {
                            toggleTorch()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.system(size: 22))
                                Text("手电筒").font(.caption2)
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 20)
                    Spacer()
                }
            }
            .navigationTitle("扫码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showAlbumPicker) {
                AlbumQRPicker { image in
                    if let text = Self.decodeQR(from: image) {
                        onResult(text)
                    } else {
                        sessionHint = "相册图片中未识别到二维码"
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .off : .on
            device.unlockForConfiguration()
            torchOn.toggle()
        } catch {
            sessionHint = "手电筒不可用"
        }
    }

    /// Offline QR decode from a still image via CIDetector.
    static func decodeQR(from image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cg)
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                        context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        let features = detector.features(in: ciImage)
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
#else
// macOS: no camera; a paste field keeps the scan entry points functional on the desktop
// build (tests + debugging) without pulling AVFoundation.
public struct QRScannerSheet: View {
    public let onResult: (String) -> Void
    @State private var text: String = ""

    public init(onResult: @escaping (String) -> Void) {
        self.onResult = onResult
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("macOS 无摄像头，粘贴二维码内容识别")
                .font(.subheadline)
            TextField("二维码内容", text: $text)
            Button("识别") {
                if !text.isEmpty { onResult(text) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
#endif
