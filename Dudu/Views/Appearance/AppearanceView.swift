import SwiftUI

// MARK: - AppearanceView · 外观
//
// Dudu-styled appearance page bound to AppearanceStudio's data APIs.
// Preset picker (warmPaper/cleanAir/nightCocoa), key color roles with
// ColorPicker, opacity sliders, reset — all engine-verified methods.

struct AppearanceView: View {
    @EnvironmentObject private var studio: AppearanceStudio

    /// The variant this page edits: follows the active variant so the
    /// ColorPicker always edits what the user is currently seeing.
    private var variant: AppearanceVariant { studio.activeVariant }

    /// Key roles exposed in the UI (not all 40 — just the main ones).
    private let roles: [(AppearanceColorRole, String)] = [
        (.canvas, "页面背景"),
        (.surface, "卡片表面"),
        (.primaryText, "主要文字"),
        (.secondaryText, "次要文字"),
        (.accent, "强调色"),
        (.userBubble, "用户气泡"),
        (.assistantBubble, "AI 气泡"),
        (.input, "输入框"),
        (.border, "边框"),
    ]

    var body: some View {
        List {
            Section("主题") {
                ForEach(AppearancePreset.allCases) { preset in
                    presetRow(preset)
                }
            }

            Section("颜色") {
                ForEach(roles, id: \.0) { role, name in
                    colorRow(role: role, name: name)
                }
            }

            Section("不透明度") {
                opacityRow("表面", value: $studio.surfaceOpacity)
                opacityRow("气泡", value: $studio.bubbleOpacity)
                opacityRow("壁纸遮罩", value: $studio.wallpaperShade)
            }

            Section {
                Button(role: .destructive) {
                    studio.resetColors()
                } label: {
                    Text("恢复默认颜色")
                        .font(DuduTheme.bodyFont())
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("当前编辑：\(variant == .dark ? "深色" : "浅色")模式。切换系统深色模式可编辑另一套。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("外观")
    }

    // MARK: Presets

    private func presetRow(_ preset: AppearancePreset) -> some View {
        Button {
            studio.applyPreset(preset)
        } label: {
            HStack(spacing: 12) {
                PresetSwatch(preset: preset)
                Text(preset.title)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                if isActive(preset) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.pink)
                }
            }
        }
    }

    /// Best-effort "which preset is active": compare canvas against presets.
    private func isActive(_ preset: AppearancePreset) -> Bool {
        let palette = preset.colors
        let ref = variant == .dark ? palette.dark[.canvas] : palette.light[.canvas]
        return studio.hex(.canvas, scope: .global, variant: variant) == (ref ?? "")
    }

    // MARK: Color roles

    private func colorRow(role: AppearanceColorRole, name: String) -> some View {
        HStack {
            Text(name)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            Spacer()
            if studio.hasOverride(role, scope: .global, variant: variant) {
                Button {
                    studio.clearOverride(role, scope: .global, variant: variant)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .buttonStyle(.plain)
            }
            ColorPicker(
                "",
                selection: studio.colorBinding(role, scope: .global, variant: variant),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    // MARK: Opacity

    private func opacityRow(_ name: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Slider(value: value, in: 0...1)
                .tint(DuduTheme.pink)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preset swatch (three dots: canvas / accent / bubble)

private struct PresetSwatch: View {
    let preset: AppearancePreset

    var body: some View {
        let dict = preset.colors.light
        HStack(spacing: -6) {
            ForEach([dict[.canvas], dict[.accent], dict[.userBubble]].compactMap { $0 }, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(DuduTheme.duduDivider, lineWidth: 1))
            }
        }
    }
}
