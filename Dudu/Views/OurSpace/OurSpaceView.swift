import SwiftUI

// MARK: - OurSpaceView · 我们的空间 container
//
// Task progress cards on top, then a Dudu-styled segmented control across
// the five sections: 状态 / 日记 / 时光 / 花园 / 稍后.

enum OurSpaceSection: String, CaseIterable, Identifiable {
    case status
    case diary
    case moments
    case garden
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "状态"
        case .diary: return "日记"
        case .moments: return "时光"
        case .garden: return "花园"
        case .later: return "稍后"
        }
    }

    var systemImage: String {
        switch self {
        case .status: return "waveform"
        case .diary: return "book"
        case .moments: return "clock"
        case .garden: return "leaf"
        case .later: return "tray"
        }
    }
}

struct OurSpaceView: View {
    @StateObject private var cards = TaskCardStore.shared

    @State private var section: OurSpaceSection = .status
    @State private var showingNewTask = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !cards.tasks.isEmpty {
                        taskCardsBlock
                    }
                    OurSpaceSegmentedControl(selection: $section)
                    sectionBody
                }
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.vertical, 12)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("我们的空间")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingNewTask) {
                NewTaskSheet(store: cards)
            }
        }
    }

    // MARK: Task cards

    private var taskCardsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("任务进度")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                if !cards.activeTasks.isEmpty {
                    Text("\(cards.activeTasks.count)")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                Spacer()
                Button {
                    showingNewTask = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("新建")
                            .font(DuduTheme.captionFont(weight: .semibold))
                    }
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DuduTheme.duduIconChip, in: Capsule())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cards.tasks) { task in
                        TaskCardView(store: cards, task: task)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .status: StatusSection()
        case .diary: DiarySection()
        case .moments: MomentsSection()
        case .garden: GardenSection()
        case .later: LaterSection()
        }
    }
}

// MARK: - Dudu-styled segmented control

struct OurSpaceSegmentedControl: View {
    @Binding var selection: OurSpaceSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(OurSpaceSection.allCases) { s in
                let selected = s == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = s
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: s.systemImage)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        Text(s.title)
                            .font(DuduTheme.captionFont(weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? DuduTheme.duduText : DuduTheme.duduTextDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selected ? DuduTheme.pinkSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }
}

// MARK: - Shared section pieces

/// Section header: small title + optional trailing action.
struct OurSpaceSectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title)
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(actionTitle)
                            .font(DuduTheme.captionFont(weight: .semibold))
                    }
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DuduTheme.duduIconChip, in: Capsule())
                }
            }
        }
    }
}

/// Honest empty state — explains what belongs here, never fake content.
struct OurSpaceEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DuduTheme.duduIconChip)
                    .frame(width: 56, height: 56)
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
            }
            Text(title)
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text(message)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }
}

/// Labeled text field for the sheets — DuduTheme only, no Form.
struct OurSpaceField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DuduTheme.captionFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduTextDim)
            TextField(placeholder, text: $text, axis: axis)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .padding(10)
                .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
        }
    }
}

/// Sheet chrome shared by all Our Space editors.
struct OurSpaceSheet<Content: View>: View {
    let title: String
    let saveTitle: String
    let canSave: Bool
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        onSave()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

/// Small chip used across sections (kind / confidence / category).
struct OurSpaceChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DuduTheme.captionFont(weight: .semibold))
            .foregroundStyle(DuduTheme.duduText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}
