import PhotosUI
import SwiftUI

// MARK: - TaskCardView · small task progress card
//
// One card per background task: name, progress bar, stage text, status chip.
// Card background: user photo (via PhotosPicker) or theme default.
// Accent: curated palette from DuduTheme (nil = theme default pink).
// Every control here does something real — no dead buttons.

struct TaskCardView: View {
    @ObservedObject var store: TaskCardStore
    let task: BackgroundTask

    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false

    @MainActor private var accent: Color { task.accentColor }
    private var pct: Int { Int((task.progress * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let uiImage = store.backgroundUIImage(for: task) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(16 / 10, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(DuduTheme.radiusChip)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(task.name)
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                cardMenu
            }

            // Progress bar — real value from the store.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DuduTheme.duduDivider)
                        .frame(height: 6)
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * CGFloat(task.progress), height: 6)
                        .animation(.easeInOut(duration: 0.4), value: task.progress)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 6)

            HStack(spacing: 6) {
                Text(task.stage.isEmpty ? "等待更新" : task.stage)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(pct)%")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .monospacedDigit()
            }

            statusChip
        }
        .padding(12)
        .frame(width: 232)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    store.setBackgroundJPEG(id: task.id, data: data)
                }
                photoItem = nil
            }
        }
    }

    // MARK: Status chip

    private var statusChip: some View {
        let dot: Color =
            switch task.status {
            case .running: accent
            case .stuck: DuduTheme.duduDestructive
            case .done: DuduTheme.duduTextDim
            }
        return HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(task.status.label)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    // MARK: Card menu — every item is wired to the store.

    private var cardMenu: some View {
        Menu {
            Button {
                showingPhotoPicker = true
            } label: {
                Label("换背景照片", systemImage: "photo")
            }
            if task.backgroundFile != nil {
                Button {
                    store.clearBackground(id: task.id)
                } label: {
                    Label("清除背景照片", systemImage: "photo.badge.minus")
                }
            }
            Menu("强调色") {
                ForEach(TaskCardAccent.allCases, id: \.self) { a in
                    Button {
                        store.setAccent(id: task.id, accent: a)
                    } label: {
                        HStack {
                            Text(a.label)
                            if task.accent == a {
                                DuduIcon(systemName: "checkmark")
                            }
                        }
                    }
                }
                Button("恢复默认") {
                    store.setAccent(id: task.id, accent: nil)
                }
            }
            if task.status == .done {
                Button {
                    store.reopen(id: task.id)
                } label: {
                    Label("重新开始", systemImage: "arrow.counterclockwise")
                }
            } else {
                Button {
                    store.markDone(id: task.id)
                } label: {
                    Label("标记完成", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                store.remove(id: task.id)
            } label: {
                Label("删除任务", systemImage: "trash")
            }
        } label: {
            DuduIcon(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DuduTheme.duduTextDim)
                .frame(width: 28, height: 28)
                .background(DuduTheme.duduIconChip, in: Circle())
        }
    }
}

// MARK: - NewTaskSheet · create a task manually from Our Space

struct NewTaskSheet: View {
    @ObservedObject var store: TaskCardStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var stage = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OurSpaceField(label: "名称", placeholder: "例如：知识库索引", text: $name)
                    OurSpaceField(label: "当前阶段", placeholder: "例如：正在读第 3/10 个文件", text: $stage)
                    Text("创建后可以在卡片菜单里换背景照片和强调色；进度由发起任务的功能实时上报。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        store.createManual(name: name, stage: stage.isEmpty ? "刚刚创建" : stage)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
