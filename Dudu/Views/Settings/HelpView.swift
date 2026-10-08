import SwiftUI

// MARK: - HelpView · 帮助中心
//
// Wave 4 P2: FAQ + feature guides + troubleshooting, all in Chinese.
// Copy follows the 文案腔调 rule (cute but not oily). Every color and
// font comes from DuduTheme — no hardcoded colors, no literal sizes.

struct HelpView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    DuduIcon(systemName: "lifepreserver.fill")
                        .font(DuduTheme.appFont(size: 15))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 30, height: 30)
                        .background(DuduTheme.duduIconChip)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    Text("用着不顺手的地方，这里都有答案。")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
                .frame(minHeight: 44)
            }

            Section {
                ForEach(HelpGuide.all) { guide in
                    NavigationLink {
                        HelpGuideView(guide: guide)
                    } label: {
                        HStack(spacing: 12) {
                            DuduIcon(systemName: guide.icon)
                                .font(DuduTheme.appFont(size: 15))
                                .foregroundStyle(DuduTheme.pink)
                                .frame(width: 30, height: 30)
                                .background(DuduTheme.duduIconChip)
                                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                            Text(guide.title)
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                        }
                        .frame(minHeight: 44)
                    }
                }
            } header: {
                Text("功能指南")
            }

            Section {
                ForEach(HelpFAQ.all) { faq in
                    DisclosureGroup {
                        Text(faq.answer)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .padding(.vertical, 4)
                    } label: {
                        Text(faq.question)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                    }
                }
            } header: {
                Text("常见问题")
            }

            Section {
                ForEach(HelpTrouble.all) { item in
                    DisclosureGroup {
                        Text(item.answer)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .padding(.vertical, 4)
                    } label: {
                        Text(item.problem)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                    }
                }
            } header: {
                Text("故障排查")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("帮助")
    }
}

// MARK: - Guide data

private struct HelpGuide: Identifiable {
    let id: String
    let title: String
    let icon: String
    let blocks: [(heading: String, body: String)]
}

private extension HelpGuide {
    static let all: [HelpGuide] = [
        HelpGuide(
            id: "chat",
            title: "聊天",
            icon: "bubble.left.and.bubble.right",
            blocks: [
                ("新开一局", "想换个话题，就新建一个会话。每个会话都是独立的，旧话题不会跑到新会话里串门。"),
                ("会话抽屉", "所有会话都在抽屉里躺着，可以搜索、可以翻旧账，再老的聊天也找得回来。"),
                ("它在想什么", "AI 动脑子的时候，气泡上会蹲着一只小黑猫。戳它一下，就能看它刚才到底在想什么。"),
                ("换个模型", "聊天界面可以切换模型。不同的模型口味不一样，多试几个，找到最对你胃口的那个。"),
            ]
        ),
        HelpGuide(
            id: "personas",
            title: "人设",
            icon: "person.crop.circle",
            blocks: [
                ("人设是什么", "给 AI 的一张身份卡：它是什么性格、怎么说话、知道些什么，都写在这里。"),
                ("怎么写才好", "越具体越好。开头几句最重要，别写正确的废话——你希望它是什么样的人，就直接写下来。"),
                ("多备几张卡", "可以建很多个人设，按心情切换。今天想找它撒娇，明天想找它干活，都行。"),
            ]
        ),
        HelpGuide(
            id: "themes",
            title: "外观与主题",
            icon: "paintpalette",
            blocks: [
                ("换主题", "外观里可以换主题包，整套颜色跟着走。看腻了就换一套，心情也跟着换。"),
                ("字体", "可以自己上传字体文件，字号在设置里调。大一点小一点，都随你。"),
                ("深色模式", "默认跟随系统，也可以自己定。晚上刷手机不刺眼。"),
            ]
        ),
        HelpGuide(
            id: "tts",
            title: "语音",
            icon: "speaker.wave.2.fill",
            blocks: [
                ("听它说话", "AI 的回复可以读出来，语音设置里打开就行。做饭洗澡的时候也能聊天。"),
                ("自己接 TTS", "有自己的语音服务？把地址和 key 粘进来，用哪家你自己定，不锁死。"),
            ]
        ),
        HelpGuide(
            id: "files",
            title: "发图和附件",
            icon: "paperclip",
            blocks: [
                ("发图", "输入框旁边点一下图片按钮，把相册里的图给它看。它看得见，别客气。"),
                ("发文件", "也可以从文件 App 里选文档发过去，它会读。"),
                ("传不动怎么办", "文件别太大，网络也要给力。实在传不动，压小一点再试。"),
            ]
        ),
    ]
}

// MARK: - FAQ data

private struct HelpFAQ: Identifiable {
    let id: Int
    let question: String
    let answer: String
}

private extension HelpFAQ {
    static let all: [HelpFAQ] = [
        HelpFAQ(id: 0, question: "嘟嘟收费吗？",
                answer: "嘟嘟本身不收费。模型服务是你自己配的，花的都是你自己的额度，用多少算多少，账在你自己手里。"),
        HelpFAQ(id: 1, question: "AI 怎么一直转圈圈？",
                answer: "先看看模型服务配好没有、网络通不通畅。额度用完了也会这样，可以去服务商后台瞧一眼。"),
        HelpFAQ(id: 2, question: "聊天记录会丢吗？",
                answer: "记录都存在手机本地，只要不卸载 App 就在。重要的会话可以在备份与恢复里导一份出来，心里踏实。"),
        HelpFAQ(id: 3, question: "换手机了怎么办？",
                answer: "备份与恢复里导出一份，新手机上再导回去，记忆就跟着一起搬家。"),
        HelpFAQ(id: 4, question: "它怎么记不住我说过的事？",
                answer: "每个会话是独立的，新会话记不得旧会话的事。想让它长期记住，就把重要的东西写进人设里。"),
        HelpFAQ(id: 5, question: "AI 回复怪怪的？",
                answer: "试试换个人设，或者把问题说得具体一点。也可以换个模型，口味这事，试过才知道。"),
    ]
}

// MARK: - Troubleshooting data

private struct HelpTrouble: Identifiable {
    let id: Int
    let problem: String
    let answer: String
}

private extension HelpTrouble {
    static let all: [HelpTrouble] = [
        HelpTrouble(id: 0, problem: "一直连接失败",
                    answer: "检查地址和 key 有没有输错一位，网络是不是好的，服务商那边有没有在维护。一个一个排除，很快就能找到。"),
        HelpTrouble(id: 1, problem: "回复特别慢",
                    answer: "可能是模型本身忙，也可能是网络慢。换个小一点的模型，或者换条网络试试。"),
        HelpTrouble(id: 2, problem: "语音播不出来",
                    answer: "先看语音设置里的开关开没开，手机是不是开了静音，再确认 TTS 服务配好了没有。"),
        HelpTrouble(id: 3, problem: "图片传不上去",
                    answer: "检查一下相册权限给没给，文件也别太大。权限在 iOS 设置里补上就行。"),
        HelpTrouble(id: 4, problem: "闪退或者卡死",
                    answer: "先完全退出 App 再重开，大多数小毛病重启就好。一直犯的话，记得更新到最新版。"),
    ]
}

// MARK: - Guide detail page

private struct HelpGuideView: View {
    let guide: HelpGuide

    var body: some View {
        List {
            ForEach(0..<guide.blocks.count, id: \.self) { i in
                let block = guide.blocks[i]
                Section {
                    Text(block.body)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                } header: {
                    Text(block.heading)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(guide.title)
    }
}
