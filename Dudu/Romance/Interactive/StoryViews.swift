//
//  D20b: 互动故事 UI —— StoryCenterView / StoryBibleView / StoryChoiceChipsView。
//
//  接线签名（供「我们的空间」与聊天输入区接线）：
//    StoryCenterView()                                              —— 我们的空间 → 互动故事
//    StoryBibleView(storyID: String)                               —— 某个故事的设定集（看得见、改得了）
//    StoryChoiceChipsView(storyID: String, onPick: @escaping (String) -> Void)
//                                                                   —— 聊天输入区上方的选项 chips
//
//  规矩：零 emoji；颜色只走 DuduTheme；文案不用纯黑纯白。

import SwiftUI

// MARK: - StoryCenterView（我们的空间 → 互动故事）

/// 故事中心：进行中的故事 + 已完结的故事（可重读），每个都能点进设定集。
@MainActor
public struct StoryCenterView: View {
    @State private var stories: [Story] = []
    @State private var showEnded: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("互动故事")
                    .font(DuduTheme.titleFont())
                    .foregroundColor(DuduTheme.duduText)
                Spacer()
                Text("\(stories.filter { $0.status != .ended }.count) 个进行中")
                    .font(DuduTheme.captionFont())
                    .foregroundColor(DuduTheme.duduTextDim)
            }
            if stories.isEmpty {
                Text("还没有故事。气氛合适时，他会提议和你一起编一个——永远不强求。")
                    .font(DuduTheme.bodyFont())
                    .foregroundColor(DuduTheme.duduTextDim)
            } else {
                ForEach(activeStories) { story in
                    NavigationLink(destination: StoryBibleView(storyID: story.id)) {
                        storyRow(story)
                    }
                    .buttonStyle(.plain)
                }
                if !endedStories.isEmpty {
                    Button(action: { showEnded.toggle() }) {
                        Text(showEnded ? "收起已完结" : "看看已完结（\(endedStories.count)）")
                            .font(DuduTheme.captionFont())
                            .foregroundColor(DuduTheme.duduTextDim)
                    }
                    if showEnded {
                        ForEach(endedStories) { story in
                            NavigationLink(destination: StoryBibleView(storyID: story.id)) {
                                storyRow(story)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(DuduTheme.pagePadding)
        .background(DuduTheme.duduCard)
        .cornerRadius(DuduTheme.radiusCard)
        .task { await reload() }
    }

    private var activeStories: [Story] { stories.filter { $0.status != .ended } }
    private var endedStories: [Story] { stories.filter { $0.status == .ended } }

    private func storyRow(_ story: Story) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("《\(story.title)》")
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundColor(DuduTheme.duduText)
                Text("\(StoryPrompt.statusWord(story.status)) · 第\(story.currentChapter)章 · \(story.scenes.count)幕")
                    .font(DuduTheme.captionFont())
                    .foregroundColor(DuduTheme.duduTextDim)
            }
            Spacer()
            Text("设定集")
                .font(DuduTheme.captionFont())
                .foregroundColor(DuduTheme.kitty)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DuduTheme.pinkSoft)
                .cornerRadius(DuduTheme.radiusPill)
        }
        .padding(.vertical, 6)
    }

    private func reload() async {
        stories = await StoryStore.shared.list(personaId: PersonaStore.currentID(), includeEnded: true)
    }
}

// MARK: - StoryBibleView（设定集：看得见、改得了）

/// 某个故事的设定集：人物 / 地点 / 关键事件，全部可增删改。
/// 暂停 / 继续 / 完结也在此操作——完结/暂停后对话框回到普通聊天。
@MainActor
public struct StoryBibleView: View {
    private let storyID: String
    @State private var story: Story?
    @State private var notice: String? = nil

    @State private var newCharName: String = ""
    @State private var newCharDesc: String = ""
    @State private var newPlaceName: String = ""
    @State private var newPlaceDesc: String = ""
    @State private var newEventText: String = ""

    public init(storyID: String) {
        self.storyID = storyID
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let story {
                    titleBlock(story)
                    statusButtons(story)
                    charactersBlock(story)
                    placesBlock(story)
                    eventsBlock(story)
                    scenesBlock(story)
                    deleteBlock(story)
                } else {
                    Text("这个故事找不到了，可能已经被删掉了。")
                        .font(DuduTheme.bodyFont())
                        .foregroundColor(DuduTheme.duduTextDim)
                }
                if let notice {
                    Text(notice)
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduTextDim)
                }
            }
            .padding(DuduTheme.pagePadding)
        }
        .background(DuduTheme.duduBackground)
        .task { await reload() }
    }

    // MARK: 段落

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(DuduTheme.titleFont())
            .foregroundColor(DuduTheme.duduText)
    }

    private func titleBlock(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("《\(story.title)》")
                .font(DuduTheme.titleFont())
                .foregroundColor(DuduTheme.duduText)
            if !story.premise.isEmpty {
                Text(story.premise)
                    .font(DuduTheme.bodyFont())
                    .foregroundColor(DuduTheme.duduTextDim)
            }
            Text("\(StoryPrompt.statusWord(story.status)) · 第\(story.currentChapter)章 · \(story.scenes.count)幕")
                .font(DuduTheme.captionFont())
                .foregroundColor(DuduTheme.duduTextDim)
        }
    }

    private func statusButtons(_ story: Story) -> some View {
        HStack(spacing: 10) {
            if story.status == .active {
                actionButton("暂停") { await setStatus(.paused, note: "故事已暂停，存档在第\(story.currentChapter)章。想继续随时喊他。") }
            }
            if story.status == .paused {
                actionButton("继续") { await setStatus(.active, note: "故事已继续。回对话框里跟他说一声，就接着讲了。") }
            }
            if story.status != .ended {
                actionButton("完结") { await setStatus(.ended, note: "故事已完结存档，随时可以回来重读。") }
            }
        }
    }

    private func actionButton(_ label: String, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
            Text(label)
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundColor(DuduTheme.kitty)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DuduTheme.pinkSoft)
                .cornerRadius(DuduTheme.radiusPill)
        }
    }

    private func charactersBlock(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("人物（\(story.bible.characters.count)）")
            ForEach(story.bible.characters) { c in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundColor(DuduTheme.duduText)
                        TextField("给TA加一句描述…", text: bindingForCharacterDesc(c))
                            .font(DuduTheme.captionFont())
                            .foregroundColor(DuduTheme.duduTextDim)
                            .textFieldStyle(.roundedBorder)
                    }
                    Spacer()
                    Button("删除") { Task { await removeBible(kind: "character", name: c.name) } }
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduDestructive)
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("名字", text: $newCharName)
                    .textFieldStyle(.roundedBorder)
                    .font(DuduTheme.bodyFont())
                TextField("描述（可选）", text: $newCharDesc)
                    .textFieldStyle(.roundedBorder)
                    .font(DuduTheme.bodyFont())
                Button("加上") {
                    Task { await addBible(kind: "character", name: newCharName, desc: newCharDesc); newCharName = ""; newCharDesc = "" }
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundColor(DuduTheme.kitty)
                .disabled(newCharName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func placesBlock(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("地点（\(story.bible.places.count)）")
            ForEach(story.bible.places) { p in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundColor(DuduTheme.duduText)
                        TextField("给这里加一句描述…", text: bindingForPlaceDesc(p))
                            .font(DuduTheme.captionFont())
                            .foregroundColor(DuduTheme.duduTextDim)
                            .textFieldStyle(.roundedBorder)
                    }
                    Spacer()
                    Button("删除") { Task { await removeBible(kind: "place", name: p.name) } }
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduDestructive)
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("地名", text: $newPlaceName)
                    .textFieldStyle(.roundedBorder)
                    .font(DuduTheme.bodyFont())
                TextField("描述（可选）", text: $newPlaceDesc)
                    .textFieldStyle(.roundedBorder)
                    .font(DuduTheme.bodyFont())
                Button("加上") {
                    Task { await addBible(kind: "place", name: newPlaceName, desc: newPlaceDesc); newPlaceName = ""; newPlaceDesc = "" }
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundColor(DuduTheme.kitty)
                .disabled(newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func eventsBlock(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("关键事件（\(story.bible.events.count)）")
            ForEach(story.bible.events) { e in
                HStack(alignment: .top) {
                    Text(e.text)
                        .font(DuduTheme.bodyFont())
                        .foregroundColor(DuduTheme.duduText)
                    Spacer()
                    Button("删除") { Task { await removeBible(kind: "event", name: e.text) } }
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduDestructive)
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("记下一件关键的事…", text: $newEventText)
                    .textFieldStyle(.roundedBorder)
                    .font(DuduTheme.bodyFont())
                Button("记下") {
                    Task { await addBible(kind: "event", name: newEventText, desc: ""); newEventText = "" }
                }
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundColor(DuduTheme.kitty)
                .disabled(newEventText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func scenesBlock(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("讲过的幕（\(story.scenes.count)）")
            ForEach(story.scenes.suffix(5)) { scene in
                VStack(alignment: .leading, spacing: 2) {
                    Text("第\(scene.chapter)章第\(scene.seq)幕")
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduTextDim)
                    Text(scene.summary)
                        .font(DuduTheme.bodyFont())
                        .foregroundColor(DuduTheme.duduText)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func deleteBlock(_ story: Story) -> some View {
        Button("删除整个故事") {
            Task {
                let ok = await StoryStore.shared.remove(id: story.id)
                notice = ok ? "《\(story.title)》已经整个删掉了。" : "删除失败。"
                await reload()
            }
        }
        .font(DuduTheme.bodyFont())
        .foregroundColor(DuduTheme.duduDestructive)
        .padding(.top, 8)
    }

    // MARK: 数据操作

    private func reload() async {
        story = await StoryStore.shared.get(id: storyID)
    }

    private func setStatus(_ status: StoryStatus, note: String) async {
        await StoryStore.shared.update(id: storyID) { $0.status = status; return true }
        notice = note
        await reload()
    }

    private func addBible(kind: String, name: String, desc: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date().timeIntervalSince1970
        await StoryStore.shared.update(id: storyID) { story in
            if kind == "character" {
                if let idx = story.bible.characters.firstIndex(where: { $0.name == n }) {
                    if !d.isEmpty { story.bible.characters[idx].desc = d }
                } else {
                    story.bible.characters.append(StoryCharacter(name: n, desc: d))
                }
            } else if kind == "place" {
                if let idx = story.bible.places.firstIndex(where: { $0.name == n }) {
                    if !d.isEmpty { story.bible.places[idx].desc = d }
                } else {
                    story.bible.places.append(StoryPlace(name: n, desc: d))
                }
            } else {
                if !story.bible.events.contains(where: { $0.text == n }) {
                    story.bible.events.append(StoryEvent(text: n, at: now))
                }
            }
            return true
        }
        await reload()
    }

    private func removeBible(kind: String, name: String) async {
        await StoryStore.shared.update(id: storyID) { story in
            if kind == "character" {
                story.bible.characters.removeAll { $0.name == name }
            } else if kind == "place" {
                story.bible.places.removeAll { $0.name == name }
            } else {
                story.bible.events.removeAll { $0.text == name }
            }
            return true
        }
        await reload()
    }

    private func bindingForCharacterDesc(_ c: StoryCharacter) -> Binding<String> {
        Binding(
            get: { story?.bible.characters.first(where: { $0.name == c.name })?.desc ?? "" },
            set: { newValue in
                let name = c.name
                Task {
                    await StoryStore.shared.update(id: storyID) { story in
                        if let idx = story.bible.characters.firstIndex(where: { $0.name == name }) {
                            story.bible.characters[idx].desc = newValue
                        }
                        return true
                    }
                    await reload()
                }
            }
        )
    }

    private func bindingForPlaceDesc(_ p: StoryPlace) -> Binding<String> {
        Binding(
            get: { story?.bible.places.first(where: { $0.name == p.name })?.desc ?? "" },
            set: { newValue in
                let name = p.name
                Task {
                    await StoryStore.shared.update(id: storyID) { story in
                        if let idx = story.bible.places.firstIndex(where: { $0.name == name }) {
                            story.bible.places[idx].desc = newValue
                        }
                        return true
                    }
                    await reload()
                }
            }
        )
    }
}

// MARK: - StoryChoiceChipsView（聊天输入区上方的选项 chips）

/// 当前对话框故事的待选选项 chips。coordinator 把它放在聊天输入区上方；
/// onPick(choiceId) 里发一条「选X」用户消息并调 story_choose（经桥工具），
/// 或直接把 choiceId 喂给已注册的 story_choose 工具。
@MainActor
public struct StoryChoiceChipsView: View {
    private let storyID: String
    private let onPick: (String) -> Void
    @State private var pending: StoryScene?

    public init(storyID: String, onPick: @escaping (String) -> Void) {
        self.storyID = storyID
        self.onPick = onPick
    }

    public var body: some View {
        Group {
            if let pending, !pending.offeredChoices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("故事正在等你选——")
                        .font(DuduTheme.captionFont())
                        .foregroundColor(DuduTheme.duduTextDim)
                    FlowChips(choices: pending.offeredChoices, onPick: onPick)
                }
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.vertical, 8)
                .task(id: storyID) { await reload() }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        guard let story = await StoryStore.shared.get(id: storyID),
              story.status == .active else {
            pending = nil
            return
        }
        pending = StoryHelpers.pendingChoiceScene(story)
    }
}

/// 简单流式 chips（无第三方依赖）。
@MainActor
private struct FlowChips: View {
    var choices: [StoryChoice]
    var onPick: (String) -> Void

    var body: some View {
        // 选项很少（A/B/C），横向排足够。
        HStack(spacing: 8) {
            ForEach(choices, id: \.id) { choice in
                Button(action: { onPick(choice.id) }) {
                    Text("\(choice.id) · \(choice.label)")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundColor(DuduTheme.kitty)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(DuduTheme.pinkSoft)
                        .cornerRadius(DuduTheme.radiusPill)
                }
            }
            Spacer()
        }
    }
}
