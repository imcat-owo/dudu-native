import SwiftUI

// MARK: - MemoryGraphView · 记忆图谱
//
// An honest visualization over REAL existing memory data — nothing is
// fabricated:
//   - Nodes = real records: MemorySeed (记忆花园), Moment (我们的时光),
//     DiaryEntry (我的日记). Never invented nodes.
//   - Edges = relationships derived from real fields only:
//       · same cluster (seeds sharing a MemoryCategory, moments sharing a kind)
//       · same calendar day (records stamped on the same real date)
//   - Empty data → honest empty state, not a made-up graph.
//
// Prior-art note: there is no memory-graph concept in the old Dudu app
// (searched openmuse/apps/mobile/src — nothing), and this repo's memory
// garden (OurSpaceStore.seeds) has no people/tags fields to link on.
// Category + date edges are the honest derivation from what exists.
// If people/tags fields ever land on MemorySeed, add a third edge kind here.
//
// Init: MemoryGraphView()

/// Init: MemoryGraphView()
@MainActor
struct MemoryGraphView: View {
    @ObservedObject private var space = OurSpaceStore.shared
    @State private var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if graphItems.isEmpty {
                emptyState
            } else {
                legendRow
                graphCanvas
            }
        }
        .sheet(item: Binding(
            get: { selectedID.flatMap { id in graphItems.first(where: { $0.id == id }) } },
            set: { selectedID = $0?.id }
        )) { item in
            NodeDetailSheet(item: item, neighbors: neighbors(of: item))
        }
    }

    // MARK: Header / legend / empty

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("记忆图谱")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text("点一个节点，看看它和谁连着")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            legendDot(color: DuduTheme.pink, label: "记忆")
            legendDot(color: DuduTheme.brandBrown, label: "时光")
            legendDot(color: DuduTheme.duduTextDim, label: "日记")
            Spacer()
            Text("\(graphItems.count) 个节点 · \(edgeCount) 条连线")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
                .monospacedDigit()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还没有可以画的记忆")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            Text("记忆花园、时光和日记里有了内容，这里会自动连成一张网。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Graph model (real data only)

    private enum NodeKind {
        case seed, moment, diary
    }

    /// Internal (not private): the sibling NodeDetailSheet needs these types.
    struct GraphItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let kind: NodeKind
        /// Edges form between items sharing a clusterKey…
        let clusterKey: String
        /// …or stamped on the same calendar day.
        let date: Date?
    }

    /// Newest-first, capped for legibility (the cap is disclosed in the legend count).
    private var graphItems: [GraphItem] {
        var items: [GraphItem] = []
        let seeds = space.seeds.sorted { $0.updatedAt > $1.updatedAt }.prefix(24)
        for s in seeds {
            items.append(GraphItem(
                id: "seed-\(s.id)",
                title: String(s.content.prefix(24)),
                detail: s.content,
                kind: .seed,
                clusterKey: "记忆·\(s.category.label)",
                date: s.createdAt))
        }
        let moments = space.moments.sorted { $0.timestamp > $1.timestamp }.prefix(8)
        for m in moments {
            items.append(GraphItem(
                id: "moment-\(m.id)",
                title: m.title,
                detail: m.detail.isEmpty ? m.title : "\(m.title)\n\(m.detail)",
                kind: .moment,
                clusterKey: "时光·\(m.kind.label)",
                date: m.timestamp))
        }
        let diary = space.diary.sorted { $0.createdAt > $1.createdAt }.prefix(8)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for d in diary {
            items.append(GraphItem(
                id: "diary-\(d.id)",
                title: d.title.isEmpty ? d.date : d.title,
                detail: d.content.isEmpty ? d.title : "\(d.title)\n\(d.content)",
                kind: .diary,
                clusterKey: "日记",
                date: df.date(from: d.date) ?? d.createdAt))
        }
        return items
    }

    struct Edge: Hashable {
        let a: String
        let b: String
        let reason: String
    }

    /// Edges derived from real shared fields only. No invented relationships.
    private var edges: [Edge] {
        let items = graphItems
        var out: [Edge] = []
        let cal = Calendar.current
        for i in items.indices {
            for j in (i + 1)..<items.count {
                let x = items[i], y = items[j]
                if x.clusterKey == y.clusterKey {
                    out.append(Edge(a: x.id, b: y.id, reason: "同类 · \(x.clusterKey)"))
                } else if let dx = x.date, let dy = y.date,
                          cal.isDate(dx, inSameDayAs: dy) {
                    let f = DateFormatter()
                    f.dateFormat = "M月d日"
                    out.append(Edge(a: x.id, b: y.id, reason: "同一天 · \(f.string(from: dx))"))
                }
            }
        }
        return out
    }

    private var edgeCount: Int { edges.count }

    private func neighbors(of item: GraphItem) -> [(GraphItem, String)] {
        let items = graphItems
        var out: [(GraphItem, String)] = []
        for e in edges {
            if e.a == item.id, let n = items.first(where: { $0.id == e.b }) {
                out.append((n, e.reason))
            } else if e.b == item.id, let n = items.first(where: { $0.id == e.a }) {
                out.append((n, e.reason))
            }
        }
        return out
    }

    // MARK: - Layout (deterministic)

    /// Cluster centers on a big circle; members on a small circle around
    /// their cluster center. Pure function of the items and size.
    private func layout(in size: CGSize) -> [String: CGPoint] {
        let items = graphItems
        guard !items.isEmpty else { return [:] }
        let clusters = Dictionary(grouping: items, by: \.clusterKey)
        let keys = clusters.keys.sorted()
        let cx = size.width / 2, cy = size.height / 2
        let bigR = min(size.width, size.height) / 2 - 44
        var pos: [String: CGPoint] = [:]
        for (ci, key) in keys.enumerated() {
            let members = clusters[key] ?? []
            let ang = 2 * Double.pi * Double(ci) / Double(max(keys.count, 1)) - Double.pi / 2
            let center = CGPoint(x: cx + CGFloat(cos(ang)) * bigR,
                                 y: cy + CGFloat(sin(ang)) * bigR)
            if members.count == 1 {
                pos[members[0].id] = center
            } else {
                let smallR: CGFloat = members.count <= 4 ? 26 : 40
                for (mi, m) in members.enumerated() {
                    let ma = 2 * Double.pi * Double(mi) / Double(members.count)
                    pos[m.id] = CGPoint(x: center.x + CGFloat(cos(ma)) * smallR,
                                        y: center.y + CGFloat(sin(ma)) * smallR)
                }
            }
        }
        return pos
    }

    private func nodeColor(_ kind: NodeKind) -> Color {
        switch kind {
        case .seed: return DuduTheme.pink
        case .moment: return DuduTheme.brandBrown
        case .diary: return DuduTheme.duduTextDim
        }
    }

    // MARK: - Canvas

    /// Colors are resolved OUTSIDE the Canvas draw closure: the closure is
    /// nonisolated and cannot touch @MainActor DuduTheme props directly, so
    /// plain Color values are captured instead.
    private var graphCanvas: some View {
        let items = graphItems
        let edges = self.edges
        let lineColor = DuduTheme.duduDivider
        let ringColor = DuduTheme.duduText
        let colors: [String: Color] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, nodeColor($0.kind)) })
        return GeometryReader { geo in
            let pos = layout(in: geo.size)
            ZStack {
                Canvas { context, _ in
                    for e in edges {
                        guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                        var path = Path()
                        path.move(to: pa)
                        path.addLine(to: pb)
                        context.stroke(path, with: .color(lineColor), lineWidth: 1)
                    }
                }
                ForEach(items) { item in
                    if let p = pos[item.id] {
                        let selected = selectedID == item.id
                        Button {
                            selectedID = item.id
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(colors[item.id] ?? lineColor)
                                    .frame(width: selected ? 22 : 16, height: selected ? 22 : 16)
                                if selected {
                                    Circle()
                                        .stroke(ringColor, lineWidth: 2)
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .position(p)
                    }
                }
            }
        }
        .frame(height: 320)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }
}

// MARK: - NodeDetailSheet · what this node really is, and why it's linked

private struct NodeDetailSheet: View {
    let item: MemoryGraphView.GraphItem
    let neighbors: [(MemoryGraphView.GraphItem, String)]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(DuduTheme.titleFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Text(item.detail)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                    }
                    if neighbors.isEmpty {
                        Text("它暂时没有连线——有了同类或同一天的记忆，会自动连上。")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("连着 \(neighbors.count) 个")
                                .font(DuduTheme.captionFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.duduTextDim)
                            ForEach(neighbors, id: \.0.id) { n, reason in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.title)
                                            .font(DuduTheme.bodyFont())
                                            .foregroundStyle(DuduTheme.duduText)
                                            .lineLimit(1)
                                        Text(reason)
                                            .font(DuduTheme.captionFont())
                                            .foregroundStyle(DuduTheme.duduTextDim)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(DuduTheme.duduBackground, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                            }
                        }
                    }
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle("这条记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关掉") { dismiss() }
                }
            }
        }
    }
}
