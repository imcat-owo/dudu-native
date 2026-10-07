import SwiftUI

// MARK: - IntimacyView · 在一起的日子
//
// Small, honest UI over IntimacyManager. No streaks, no gamified cruft —
// her taste is restrained.

/// Init: IntimacyView()
@MainActor
struct IntimacyView: View {
    @ObservedObject private var manager = IntimacyManager.shared
    @State private var pickingDate = false
    @State private var draftDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if let days = manager.daysTogether, let phase = manager.phase {
                daysCard(days: days, phase: phase)
            } else {
                noDateCard
            }
            milestonesCard
        }
        .sheet(isPresented: $pickingDate) {
            datePickerSheet
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("在一起的日子")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Text("安安静静地数着")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { manager.celebrationsEnabled },
                set: { manager.celebrationsEnabled = $0 }
            ))
            .labelsHidden()
            .tint(DuduTheme.pink)
        }
    }

    // MARK: Days card

    private func daysCard(days: Int, phase: IntimacyPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(days)")
                    .font(DuduTheme.headingFont(delta: 14))
                    .foregroundStyle(DuduTheme.duduText)
                    .monospacedDigit()
                Text("天")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Text(phase.label)
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DuduTheme.pinkSoft, in: Capsule())
            }
            Text(phase.line)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Button {
                draftDate = manager.togetherSince ?? Date()
                pickingDate = true
            } label: {
                Text("改日期")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: No date yet (honest — no invented line)

    private var noDateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没告诉我从哪天算起")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            Text("告诉我你们在一起的那一天，我就从那天开始数。没说之前，我不会瞎编。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Button {
                draftDate = Date()
                pickingDate = true
            } label: {
                Text("告诉他")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DuduTheme.pinkSoft, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: Milestones

    private var milestonesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("里程碑")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            ForEach(IntimacyManager.milestoneDays, id: \.self) { days in
                milestoneRow(days: days)
            }
            Text("只在 7 / 30 / 100 / 365 天庆祝一次，不打卡、不催促。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .padding(14)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private func milestoneRow(days: Int) -> some View {
        let state = manager.state(of: days)
        return HStack(spacing: 10) {
            Image(systemName: stateIcon(state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state == .upcoming ? DuduTheme.duduTextDim : DuduTheme.duduText)
                .frame(width: 22)
            Text("\(days) 天")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .monospacedDigit()
            Spacer()
            Text(stateLabel(state))
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            if state == .reached {
                Button {
                    manager.markCelebrated(days: days)
                } label: {
                    Text("庆祝过了")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    manager.skipMilestone(days: days)
                } label: {
                    Text("跳过")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stateIcon(_ s: IntimacyManager.MilestoneState) -> String {
        switch s {
        case .upcoming: return "circle"
        case .reached: return "sparkles"
        case .celebrated: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func stateLabel(_ s: IntimacyManager.MilestoneState) -> String {
        switch s {
        case .upcoming: return "还没到"
        case .reached: return "到了"
        case .celebrated: return "庆祝过"
        case .skipped: return "已跳过"
        }
    }

    // MARK: Date picker

    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("在一起的那一天", selection: $draftDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(DuduTheme.pink)
                    .padding(DuduTheme.pagePadding)
                Spacer()
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("哪一天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { pickingDate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存下") {
                        manager.setTogetherSince(draftDate)
                        pickingDate = false
                    }
                }
            }
        }
    }
}
