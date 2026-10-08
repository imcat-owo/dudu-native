import SwiftUI

// MARK: - PersonaDialsView · 人格维度滑杆
//
// Her-only UI: five sliders, 0–100 each, immediate effect. The AI has no tool
// to move these — this view is the only writer.

/// Init: PersonaDialsView(personaID: String)
@MainActor
struct PersonaDialsView: View {
    let personaID: String

    @ObservedObject private var store = PersonaDialsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            ForEach(PersonaDial.allCases, id: \.self) { dial in
                dialRow(dial)
            }
            resetRow
        }
        .onAppear {
            store.open(personaID: personaID)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("人格维度")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text("只有你能动这些滑杆，拖完立刻生效")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    // MARK: Dial rows

    private func dialRow(_ dial: PersonaDial) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: dial.systemImage)
                    .font(DuduTheme.appFont(size: 13, weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .frame(width: 22)
                Text(dial.title)
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Text("\(Int(store.value(for: dial).rounded()))")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .monospacedDigit()
                    .frame(minWidth: 30, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { store.value(for: dial) },
                    set: { store.setDial(dial, value: $0) }
                ),
                in: 0...100,
                step: 1
            )
            .tint(DuduTheme.pink)
            Text(dial.hint)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .padding(12)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: Reset

    private var resetRow: some View {
        HStack {
            Spacer()
            Button {
                store.resetAll()
            } label: {
                Text("回到中间值")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DuduTheme.duduCard, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
