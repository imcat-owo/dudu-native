//
//  D20b: 照片涂鸦 DoodleManager —— ported from
//  ~/workspace/openmuse/apps/mobile/src/manuals/doodle.ts （纯逻辑层）。
//
//  她发来照片时，AI 可以在上面涂鸦——画颗心、圈个东西、
//  指过去的箭头、手写风小纸条——再发回去。像一起在拍立得上乱画。
//
//  诚实是这个功能的全部：
//  - 只在 AI 真正「看见」的地方落笔（识图看到的）。看不见就瞎画时必须明说。
//  - 返回的 drew 逐条写清画了什么、在哪——模型回复时用这些原话，不许添油加醋。
//  - 最多 8 个动作；两三个最合适。这是亲昵，不是乱涂。
//
//  注意：涂鸦是本地 CoreGraphics 落笔，不走 AI 图片生成管线——
//  所以不需要 PhotoShareManager 的图片管线。输入必须是她照片的真实路径；
//  拿不到真实路径就不画，绝不编路径、绝不用库存图。

import Foundation
import UIKit

// MARK: - DoodleAction

public enum DoodleKind: String, Sendable {
    case heart
    case circle
    case arrow
    case text
}

public struct DoodleAction: Sendable {
    public var kind: DoodleKind
    /// 0..1，0,0 = 左上角。
    public var x: Double
    public var y: Double
    /// heart：占照片短边的比例（默认 0.12）。circle：半径（同口径，默认 0.1）。
    public var size: Double?
    /// arrow 的起点。
    public var x1: Double?
    public var y1: Double?
    /// text 的内容（最多 40 字，可爱不许刻薄）。
    public var text: String?
    /// pink/red/yellow/blue/green/purple/white/black 或 #hex。默认 pink。
    public var colorName: String?

    public init(kind: DoodleKind, x: Double, y: Double, size: Double? = nil,
                x1: Double? = nil, y1: Double? = nil, text: String? = nil, colorName: String? = nil) {
        self.kind = kind
        self.x = x
        self.y = y
        self.size = size
        self.x1 = x1
        self.y1 = y1
        self.text = text
        self.colorName = colorName
    }
}

// MARK: - DoodleManager

public enum DoodleManager {
    public static let maxActions = 8

    public enum DoodleError: Error, LocalizedError {
        case photoNotFound(String)
        case notAnImage(String)
        case noActions
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .photoNotFound(let p): return "找不到这张照片：\(p)。拿不到她照片的真实路径就不画，不编路径。"
            case .notAnImage(let p): return "这个文件不是图片，打不开：\(p)"
            case .noActions: return "没有有效的涂鸦动作（最多 \(DoodleManager.maxActions) 个）。"
            case .writeFailed(let m): return "涂鸦图片保存失败：\(m)"
            }
        }
    }

    public struct DoodleResult: Sendable {
        /// 画好的 PNG 本地路径。
        public var outputURL: URL
        /// 逐条写清画了什么、在哪——模型回复时用这些原话，不许添油加醋。
        public var drew: [String]
        public init(outputURL: URL, drew: [String]) {
            self.outputURL = outputURL
            self.drew = drew
        }
    }

    // MARK: 解析（工具参数 → 动作）

    /// 从工具的 actions 数组（JSON 对象数组）解析，最多取 8 个。
    public static func parseActions(_ raw: [Any]) -> [DoodleAction] {
        var out: [DoodleAction] = []
        for item in raw.prefix(maxActions) {
            guard let d = item as? [String: Any],
                  let kindRaw = d["kind"] as? String,
                  let kind = DoodleKind(rawValue: kindRaw) else { continue }
            func num(_ k: String) -> Double? {
                if let n = d[k] as? NSNumber { return n.doubleValue }
                return nil
            }
            let action = DoodleAction(
                kind: kind,
                x: num("x") ?? 0.5,
                y: num("y") ?? 0.5,
                size: num("size"),
                x1: num("x1"), y1: num("y1"),
                text: (d["text"] as? String).map { String($0.prefix(40)) },
                colorName: d["color"] as? String
            )
            out.append(action)
        }
        return out
    }

    // MARK: 落笔

    /// 在她的照片上涂鸦。返回画好的 PNG 路径 + drew 清单。
    public static func doodle(photoURL: URL, actions: [DoodleAction]) throws -> DoodleResult {
        guard FileManager.default.fileExists(atPath: photoURL.path) else {
            throw DoodleError.photoNotFound(photoURL.path)
        }
        guard let image = UIImage(contentsOfFile: photoURL.path) else {
            throw DoodleError.notAnImage(photoURL.path)
        }
        let valid = Array(actions.prefix(maxActions))
        guard !valid.isEmpty else { throw DoodleError.noActions }

        let size = image.size
        let shortEdge = min(size.width, size.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let drew: [String] = valid.map { drewLine(for: $0) }
        let doodled = renderer.image { ctx in
            image.draw(at: .zero)
            let cg = ctx.cgContext
            for action in valid {
                draw(action, in: cg, imageSize: size, shortEdge: shortEdge)
            }
        }

        let outDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuduDoodles", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("doodle_\(UUID().uuidString).png")
        guard let png = doodled.pngData() else {
            throw DoodleError.writeFailed("PNG 编码失败")
        }
        do {
            try png.write(to: outURL, options: .atomic)
        } catch {
            throw DoodleError.writeFailed(error.localizedDescription)
        }
        return DoodleResult(outputURL: outURL, drew: drew)
    }

    // MARK: 画笔实现

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    private static func doodleColor(_ name: String?) -> UIColor {
        switch (name ?? "pink").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pink": return UIColor(red: 1.0, green: 0.48, blue: 0.67, alpha: 1)
        case "red": return UIColor(red: 0.90, green: 0.28, blue: 0.30, alpha: 1)
        case "yellow": return UIColor(red: 1.0, green: 0.77, blue: 0.24, alpha: 1)
        case "blue": return UIColor(red: 0.30, green: 0.60, blue: 1.0, alpha: 1)
        case "green": return UIColor(red: 0.27, green: 0.65, blue: 0.35, alpha: 1)
        case "purple": return UIColor(red: 0.56, green: 0.31, blue: 0.78, alpha: 1)
        case "white": return .white
        case "black": return UIColor(white: 0.1, alpha: 1)
        default:
            var hex = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
            if hex.count == 6, let v = UInt32(hex, radix: 16) {
                return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                               green: CGFloat((v >> 8) & 0xFF) / 255,
                               blue: CGFloat(v & 0xFF) / 255, alpha: 1)
            }
            return UIColor(red: 1.0, green: 0.48, blue: 0.67, alpha: 1)
        }
    }

    private static func colorWord(_ name: String?) -> String {
        switch (name ?? "pink").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pink": return "粉色"
        case "red": return "红色"
        case "yellow": return "黄色"
        case "blue": return "蓝色"
        case "green": return "绿色"
        case "purple": return "紫色"
        case "white": return "白色"
        case "black": return "黑色"
        default: return name ?? "粉色"
        }
    }

    private static func drewLine(for action: DoodleAction) -> String {
        let c = colorWord(action.colorName)
        let pos = "x \(String(format: "%.2f", clamp01(action.x)))，y \(String(format: "%.2f", clamp01(action.y)))"
        switch action.kind {
        case .heart: return "画了一颗\(c)的心（\(pos)）"
        case .circle: return "画了一个\(c)的圈（\(pos)）"
        case .arrow:
            let from = "从 x \(String(format: "%.2f", clamp01(action.x1 ?? action.x)))，y \(String(format: "%.2f", clamp01(action.y1 ?? action.y)))"
            return "画了一个\(c)的箭头（\(from)，指向 \(pos)）"
        case .text:
            let t = action.text ?? ""
            return "写了一句手写风小字「\(t)」（\(pos)，\(c)）"
        }
    }

    private static func draw(_ action: DoodleAction, in cg: CGContext, imageSize: CGSize, shortEdge: CGFloat) {
        let color = doodleColor(action.colorName)
        let lineWidth = max(2, shortEdge * 0.008)
        let px = CGFloat(clamp01(action.x)) * imageSize.width
        let py = CGFloat(clamp01(action.y)) * imageSize.height

        switch action.kind {
        case .heart:
            let s = CGFloat(action.size ?? 0.12) * shortEdge
            let rect = CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)
            cg.setFillColor(color.cgColor)
            cg.addPath(heartPath(in: rect))
            cg.fillPath()

        case .circle:
            let r = CGFloat(action.size ?? 0.1) * shortEdge
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(lineWidth)
            cg.strokeEllipse(in: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2))

        case .arrow:
            let x1 = CGFloat(clamp01(action.x1 ?? action.x)) * imageSize.width
            let y1 = CGFloat(clamp01(action.y1 ?? action.y)) * imageSize.height
            let headLen = max(8, shortEdge * 0.03)
            let angle = atan2(py - y1, px - x1)
            cg.setStrokeColor(color.cgColor)
            cg.setFillColor(color.cgColor)
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.move(to: CGPoint(x: x1, y: y1))
            cg.addLine(to: CGPoint(x: px, y: py))
            cg.strokePath()
            // 箭头。
            cg.move(to: CGPoint(x: px, y: py))
            cg.addLine(to: CGPoint(x: px - headLen * cos(angle - 0.45), y: py - headLen * sin(angle - 0.45)))
            cg.addLine(to: CGPoint(x: px - headLen * cos(angle + 0.45), y: py - headLen * sin(angle + 0.45)))
            cg.closePath()
            cg.fillPath()

        case .text:
            let text = (action.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let fontSize = max(14, shortEdge * 0.045)
            // 手写风：粗圆体 + 轻微倾斜。
            let font = UIFont.boldSystemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let ns = text as NSString
            let textSize = ns.size(withAttributes: attrs)
            cg.saveGState()
            cg.translateBy(x: px, y: py)
            cg.rotate(by: -0.06)
            // 白色细描边，压在照片上也看得清。
            cg.setTextDrawingMode(.fillStroke)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            cg.setLineWidth(max(1, fontSize * 0.06))
            ns.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attrs)
            cg.restoreGState()
        }
    }

    /// 给定外接矩形的心形路径。
    private static func heartPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.95))
        path.addCurve(to: CGPoint(x: x + w * 0.08, y: y + h * 0.42),
                      control1: CGPoint(x: x + w * 0.18, y: y + h * 0.78),
                      control2: CGPoint(x: x - w * 0.02, y: y + h * 0.58))
        path.addCurve(to: CGPoint(x: x + w * 0.08, y: y + h * 0.14),
                      control1: CGPoint(x: x + w * 0.02, y: y + h * 0.28),
                      control2: CGPoint(x: x + w * 0.02, y: y + h * 0.18))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.32),
                      control1: CGPoint(x: x + w * 0.2, y: y - h * 0.02),
                      control2: CGPoint(x: x + w * 0.38, y: y + h * 0.12))
        path.addCurve(to: CGPoint(x: x + w * 0.92, y: y + h * 0.14),
                      control1: CGPoint(x: x + w * 0.62, y: y + h * 0.12),
                      control2: CGPoint(x: x + w * 0.8, y: y - h * 0.02))
        path.addCurve(to: CGPoint(x: x + w * 0.92, y: y + h * 0.42),
                      control1: CGPoint(x: x + w * 0.98, y: y + h * 0.18),
                      control2: CGPoint(x: x + w * 0.98, y: y + h * 0.28))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.95),
                      control1: CGPoint(x: x + w * 1.02, y: y + h * 0.58),
                      control2: CGPoint(x: x + w * 0.82, y: y + h * 0.78))
        path.closeSubpath()
        return path
    }
}
