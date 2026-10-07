import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - QRCodeImage · 二维码渲染（共享）
//
// Same CIFilter.qrCodeGenerator pattern ThemePackShareView uses — one shared
// renderer so new share surfaces don't each reimplement it.

enum QRCodeImage {
    /// Render a QR code UIImage for the given text, or nil when the text
    /// can't be encoded. Correction level M, integer scale, no interpolation
    /// (kept sharp by the SwiftUI wrapper).
    static func image(from string: String, scale: CGFloat = 6) -> UIImage? {
        guard let data = string.data(using: .utf8), !data.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// SwiftUI wrapper: sharp, non-interpolated QR image in a card frame.
struct QRCodeImageView: View {
    let text: String
    var size: CGFloat = 200

    var body: some View {
        Group {
            if let uiImage = QRCodeImage.image(from: text) {
                Image(uiImage: uiImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .background(DuduTheme.duduCard)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    .overlay(
                        RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                            .stroke(DuduTheme.duduDivider, lineWidth: 1)
                    )
            } else {
                Text(AppLocalized("shareimport.qrFailed"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: size, height: size)
            }
        }
    }
}
