//
//  D20a (2026-10-08): proactive settings + mood timeline (Our Space wiring).
//
//  Exposed for the Our Space page (coordinator wires these in — this file
//  never touches OurSpaceView.swift itself):
//    - ProactiveSettingsView()  — 自发帖 / 每日心情 / 次日跟进 / 共享上限
//    - MoodTimelineView()       — 心情记录时间线（新的在前）
//
//  Rules: zero emoji. Every color from DuduTheme. Text never pure
//  black/white. DuduTheme is @MainActor — these Views are @MainActor, and
//  theme colors are only referenced inside view bodies / helpers.

import SwiftUI

// MARK: - Proactive settings (Our Space section)

@MainActor
struct ProactiveSettingsView: View {
    @ObservedObject private var selfPost = SelfPostManager.shared
    @ObservedObject private var mood = MoodCheckInManager.shared
    @ObservedObject private var followUp = FollowUpManager.shared
    @ObservedObject private var engine = ProactiveEngine.shared

    /// Her valid check-in hours: never 06:00–16:00 (her sleep window).
    private let validHours = [16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5]

    init() {}

    var body: some View {
        List {
            moodSection
            selfPostSection
            followUpSection
            sharedCapSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DuduTheme.duduBackground)
        .navigationTitle("主动一点")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 每日心情

    private var moodSection: some View {
        Section {
            Toggle("每天问我一次心情", isOn: Binding(
                get: { mood.config.enabled },
                set: { mood.setEnabled($0) }
            ))
            .tint(DuduTheme.pink)
            HStack {
                Text("几点问")
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Picker("几点问", selection: Binding(
                    get: { mood.config.hour },
                    set: { _ = mood.setHour($0) }
                )) {
                    ForEach(validHours, id: \.self) { h in
                        Text("\(h):00").tag(h)
                    }
                }
                .pickerStyle(.menu)
            }
            NavigationLink {
                MoodTimelineView()
            } label: {
                Text("心情时间线")
                    .foregroundStyle(DuduTheme.duduText)
            }
        } header: {
            Text("每日心情")
        } footer: {
            Text("每天在你定的时间问一句。今天已经记过、你刚在线、或昨天没回，今天就不问。")
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    // MARK: AI 自发帖

    private var selfPostSection: some View {
        Section {
            Toggle("允许 AI 自己发动态", isOn: Binding(
                get: { selfPost.config.enabled },
                set: { v in selfPost.updateConfig(byHer: true) { $0.enabled = v } }
            ))
            .tint(DuduTheme.pink)

            VStack(alignment: .leading, spacing: 8) {
                Text("安静时段（\(selfPost.config.slotHours.count)/5）")
                    .foregroundStyle(DuduTheme.duduText)
                    .font(.subheadline)
                ForEach(selfPost.config.slotHours.sorted(), id: \.self) { h in
                    HStack {
                        Text("\(h):00（上海时间）")
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { h },
                            set: { nv in moveSlot(from: h, to: nv) }
                        ), in: 16...23)
                        .labelsHidden()
                        Button("移除") { removeSlot(h) }
                            .font(.caption)
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                }
                if selfPost.config.slotHours.count < 5 {
                    Button("加一个时段") { addSlot() }
                        .foregroundStyle(DuduTheme.brandBrown)
                }
            }

            HStack {
                Text("每天最多发")
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Stepper("\(selfPost.config.dailyCap) 条", value: Binding(
                    get: { selfPost.config.dailyCap },
                    set: { v in selfPost.updateConfig(byHer: true) { $0.dailyCap = min(3, max(0, v)) } }
                ), in: 0...3)
            }

            let log = selfPost.todaysDecisions()
            if !log.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 今天想发没发")
                        .foregroundStyle(DuduTheme.duduText)
                        .font(.subheadline)
                    ForEach(log.prefix(10)) { d in
                        HStack(alignment: .top, spacing: 8) {
                            Text(ProactiveClock.hourMinute(of: Date(timeIntervalSince1970: d.at)))
                                .font(.caption)
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .frame(width: 44, alignment: .leading)
                            Text(d.text)
                                .font(.caption)
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                }
            }
        } header: {
            Text("AI 自发帖")
        } footer: {
            Text("一天几个安静时刻，AI 会自己决定要不要发一条动态。想发没发都会记在这里。跳过是安静的，不会吵你；时段绝不会落在你睡觉的时间。")
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    private func addSlot() {
        let used = Set(selfPost.config.slotHours)
        let candidate = [17, 20, 23, 18, 19, 21, 22, 16, 0, 1, 2, 3, 4, 5]
            .first { !used.contains($0) } ?? 20
        selfPost.updateConfig(byHer: true) { $0.slotHours.append(candidate) }
    }

    private func removeSlot(_ h: Int) {
        selfPost.updateConfig(byHer: true) { $0.slotHours.removeAll { $0 == h } }
    }

    private func moveSlot(from old: Int, to new: Int) {
        guard (16...23).contains(new) || (0...5).contains(new) else { return }
        selfPost.updateConfig(byHer: true) { c in
            c.slotHours.removeAll { $0 == old }
            c.slotHours.append(new)
        }
    }

    // MARK: 次日跟进

    private var followUpSection: some View {
        Section {
            Toggle("次日跟进", isOn: Binding(
                get: { followUp.masterEnabled },
                set: { followUp.masterEnabled = $0 }
            ))
            .tint(DuduTheme.pink)
            let items = followUp.pendingItems()
            if items.isEmpty {
                Text("现在没有在跟进的事。你在聊天里提到将来的事，我会记下来，第二天问你一次。")
                    .font(.caption)
                    .foregroundStyle(DuduTheme.duduTextDim)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .foregroundStyle(DuduTheme.duduText)
                            .font(.subheadline)
                        Text(fireText(for: item))
                            .font(.caption)
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                .onDelete { idx in
                    for i in idx { followUp.delete(id: items[i].id) }
                }
            }
        } header: {
            Text("次日跟进")
        } footer: {
            Text("只跟你亲口提过的事，记下时会亲口告诉你。事件第二天 17:00 问一次，只问一次；你后来自己提到了就自动取消。左滑可删。")
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    private func fireText(for item: FollowUpItem) -> String {
        guard let fire = item.fireDate else { return "时间未知" }
        return "\(ProactiveClock.dateKey(of: fire)) \(ProactiveClock.hourMinute(of: fire)) 问一次（上海时间）"
    }

    // MARK: 共享上限

    private var sharedCapSection: some View {
        Section {
            HStack {
                Text("每天主动找你的次数上限")
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Stepper("\(engine.sharedDailyCap) 次", value: Binding(
                    get: { engine.sharedDailyCap },
                    set: { engine.sharedDailyCap = $0 }
                ), in: 0...6)
            }
            let sent = engine.sendsToday()
            if !sent.isEmpty {
                Text("今天已经主动找过你 \(sent.count) 次。")
                    .font(.caption)
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        } header: {
            Text("共享上限")
        } footer: {
            Text("自发帖、次日跟进、每日心情共用这个上限。超了就安静，如实记下来。")
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }
}

// MARK: - Mood timeline

@MainActor
struct MoodTimelineView: View {
    @ObservedObject private var mood = MoodCheckInManager.shared

    init() {}

    var body: some View {
        List {
            let items = mood.timeline()
            if items.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有心情记录")
                            .foregroundStyle(DuduTheme.duduText)
                            .font(DuduTheme.headingFont(delta: 0))
                        Text("你在聊天里说说今天怎么样，我就会记下来，出现在这里。")
                            .font(.caption)
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                ForEach(items) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.dateKey)
                                .font(.caption)
                                .foregroundStyle(DuduTheme.duduTextDim)
                            Spacer()
                            Text(entry.source == "checkin" ? "问起" : "聊天里说的")
                                .font(.caption)
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        Text(entry.mood)
                            .foregroundStyle(DuduTheme.duduText)
                            .font(DuduTheme.headingFont(delta: -2))
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.subheadline)
                                .foregroundStyle(DuduTheme.duduText)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { idx in
                    let items = mood.timeline()
                    for i in idx { mood.delete(dateKey: items[i].dateKey) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DuduTheme.duduBackground)
        .navigationTitle("心情时间线")
        .navigationBarTitleDisplayMode(.inline)
    }
}
