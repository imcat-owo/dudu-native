import AVFoundation
import SwiftUI
import UIKit

// MARK: - ProviderQRScanView · 扫码导入服务配置
//
// Native port of old Dudu's ScanSheet (api-settings.tsx B12) — the
// provider-context scanner, not the standalone extras scanner:
//   - camera permission states (request / denied → open Settings, same as
//     old Dudu's "once denied, only Settings brings it back" note)
//   - scan a dudu-provider:v1: code → validate → import as a NEW service
//     (old D44: never celebrate before the save lands — the native store
//     write is synchronous, so the result shown IS the post-save result)
//   - paste fallback (apigroup.share.pastePh)
//   - honest errors on bad codes (apigroup.share.invalid); a code that is
//     not a provider share is reported as such, never force-imported

struct ProviderQRScanView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @EnvironmentObject private var nav: SettingsNavigator
    @Environment(\.dismiss) private var dismiss

    @State private var permission: AVAuthorizationStatus = .notDetermined
    @State private var paste = ""
    @State private var outcome: ScanOutcome?
    @State private var scannerID = UUID()

    enum ScanOutcome {
        case imported(result: ProviderShareImportResult)
        case invalid
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    permissionBody
                }
                if outcome == nil, permission == .authorized {
                    Section {
                        Text(AppLocalized("apigroup.share.pastePh"))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                        TextEditor(text: $paste)
                            .font(DuduTheme.monoFont(size: 11))
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(minHeight: 80)
                        Button(AppLocalized("extras.scan.handle")) {
                            handleText(paste)
                        }
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                        .disabled(paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(AppLocalized("apigroup.share.scan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("common.close")) { dismiss() }
                }
            }
            .onAppear { refreshPermission() }
        }
    }

    // MARK: - Permission states

    @ViewBuilder
    private var permissionBody: some View {
        switch permission {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalized("apigroup.share.cameraDenied"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                Button(AppLocalized("extras.scan.allowCamera")) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { refreshPermission() }
                    }
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.pink)
            }
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalized("apigroup.share.cameraDenied"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                Button(AppLocalized("apigroup.share.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.pink)
            }
        case .authorized:
            if let outcome {
                resultCard(outcome)
            } else {
                VStack(spacing: 10) {
                    QRCodeScannerView(onCode: handleText)
                        .id(scannerID)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
                        .overlay(
                            RoundedRectangle(cornerRadius: DuduTheme.radiusCard)
                                .stroke(DuduTheme.duduDivider, lineWidth: 1)
                        )
                    Text(AppLocalized("extras.scan.hint"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 4)
            }
        @unknown default:
            Text(AppLocalized("apigroup.share.cameraDenied"))
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func resultCard(_ outcome: ScanOutcome) -> some View {
        switch outcome {
        case .invalid:
            VStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(DuduTheme.duduTextDim)
                Text(AppLocalized("apigroup.share.invalid"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .multilineTextAlignment(.center)
                Button(AppLocalized("extras.scan.scanAgain")) { reset() }
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        case .imported(let result):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DuduTheme.success)
                Text(String(format: AppLocalized("extras.scan.providerImported"), result.name))
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                    .multilineTextAlignment(.center)
                ForEach(warningTexts(result.warnings), id: \.self) { text in
                    Text(text)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 16) {
                    Button(AppLocalized("shareimport.viewDetail")) {
                        let id = result.instanceId
                        dismiss()
                        DispatchQueue.main.async {
                            nav.path.append(SettingsRoute.providerDetail(id))
                        }
                    }
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
                    Button(AppLocalized("extras.scan.scanAgain")) { reset() }
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Logic

    private func refreshPermission() {
        permission = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func handleText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let payload = ProviderShareCodec.decodeShare(trimmed) else {
            outcome = .invalid
            return
        }
        let result = ProviderShareImporter.importPayload(payload, into: store)
        outcome = .imported(result: result)
    }

    private func reset() {
        outcome = nil
        paste = ""
        scannerID = UUID()
    }

    private func warningTexts(_ warnings: [ProviderShareImportWarning]) -> [String] {
        warnings.map { warning in
            switch warning {
            case .headersDropped:
                return AppLocalized("shareimport.headersDropped")
            case .bodyExtrasDropped:
                return AppLocalized("shareimport.bodyExtrasDropped")
            case .keyPoolTruncated(let n):
                return String(format: AppLocalized("shareimport.poolTruncated"), "\(n)")
            case .noKey:
                return AppLocalized("shareimport.noKey")
            case .noBaseURL:
                return AppLocalized("shareimport.noBaseURL")
            }
        }
    }
}

// MARK: - Camera QR scanner (AVFoundation)

/// Live camera QR reader. Fires onCode once per distinct code value;
/// remount (via .id) to scan again.
struct QRCodeScannerView: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeUIView(context: Context) -> QRScannerUIView {
        let view = QRScannerUIView()
        view.onCode = onCode
        return view
    }

    func updateUIView(_ uiView: QRScannerUIView, context: Context) {}

    static func dismantleUIView(_ uiView: QRScannerUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class QRScannerUIView: UIView {
    var onCode: ((String) -> Void)?
    private var session: AVCaptureSession?
    private var lastValue: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        setup()
    }

    private func setup() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        let session = AVCaptureSession()
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        (layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.frame = bounds
    }

    func stop() {
        session?.stopRunning()
        session = nil
    }
}

extension QRScannerUIView: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue,
              !value.isEmpty,
              value != lastValue
        else { return }
        lastValue = value
        onCode?(value)
    }
}
