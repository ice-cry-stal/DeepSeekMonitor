import SwiftUI

// MARK: - 条形图数据

private struct BarRowData {
    let segments: [(label: String, value: Double, color: Color)]
    let totalLabel: String
    let extraLabel: String?   // Token 条命中率
    let modelName: String
    let displayName: String
    let requestCount: Int
    let showAbove: Bool       // V4Flash 标签在上方
}

// MARK: - Dashboard 主视图

struct DashboardView: View {
    let viewModel: ViewModel
    @State private var showSettings = false

    @AppStorage("dashboardHeight") private var savedHeight: Double = 620
    @State private var displayHeight: Double = 620
    @State private var windowRef: NSWindow?

    private let pricing = Dictionary.deepseekPricing

    private let hitColor   = Color.green
    private let missColor  = Color(red: 0.4, green: 0.75, blue: 0.4)
    private let outputColor = Color.blue

    private let modelOrder: [String] = ["deepseek-v4-flash", "deepseek-v4-pro"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    headerRow

                    if viewModel.aggregateUsage.isEmpty {
                        emptyState
                    } else {
                        legendRow

                        let hasToday = !viewModel.todayAggregateUsage.isEmpty

                        // 今日费用构成
                        if hasToday {
                            costSection(title: "今日费用构成", models: viewModel.todayAggregateUsage)
                        }

                        // 今日 Token 消耗
                        if hasToday {
                            tokenSection(title: "今日 Token 消耗", models: viewModel.todayAggregateUsage)
                        }

                        // 本月费用构成
                        costSection(title: "本月费用构成", models: viewModel.aggregateUsage)

                        // 本月 Token 消耗
                        tokenSection(title: "本月 Token 消耗", models: viewModel.aggregateUsage)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            toolbarRow
        }
        .glassBackground(blendingMode: .withinWindow)
        .frame(width: 430, height: max(400, min(1200, displayHeight)))
        .transaction { transaction in
            transaction.animation = nil
        }
        .background(WindowRefCapture(window: $windowRef))
        .overlay(alignment: .bottom) {
            ZStack(alignment: .center) {
                BottomResizeHandle(
                    height: $displayHeight,
                    savedHeight: $savedHeight,
                    window: windowRef
                )
                .frame(height: 10)

                Capsule()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 36, height: 3)
            }
        }
        .overlay {
            if showSettings {
                SettingsOverlay(viewModel: viewModel, isPresented: $showSettings)
            }
        }
        .onAppear {
            displayHeight = savedHeight
        }
    }

    // MARK: - 顶部

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerItem(label: "剩余",
                       amount: viewModel.remainingBalance?.cnyDisplay ?? "--",
                       color: .green)
            divider
            headerItem(label: "今日",
                       amount: viewModel.todayCost.cnyDisplay,
                       color: .orange,
                       subtitle: "每日8:00更新")
            divider
            headerItem(label: "本月",
                       amount: viewModel.totalCost.cnyDisplay,
                       color: .blue)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .glassCard()
    }

    private func headerItem(label: String, amount: String, color: Color, subtitle: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(amount).font(.headline).fontWeight(.bold).foregroundColor(color)
            if let subtitle {
                Text(subtitle).font(.system(size: 8)).foregroundColor(.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1, height: 30)
    }

    // MARK: - 图例（缓存未命中 → 缓存命中 → 输出）

    private var legendRow: some View {
        HStack(spacing: 16) {
            legendItem(color: missColor, label: "缓存未命中")
            legendItem(color: hitColor, label: "缓存命中")
            legendItem(color: outputColor, label: "输出")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - 费用条形图

    private func costSection(title: String, models: [AggregateModelUsage]) -> some View {
        let ordered = sorted(models)
        let rows: [BarRowData] = ordered.map { model in
            let c = viewModel.costBreakdown(model: model)
            let total = c.hit + c.miss + c.output
            let modelIdx = modelOrder.firstIndex(of: model.modelName) ?? 0
            let avgCost = model.totalTokens > 0 ? total / Double(model.totalTokens) * 100_000_000 : 0
            let avgCostLabel = model.totalTokens >= 30_000_000
                ? String(format: "每亿Token平均花费\n%.2f元", avgCost)
                : nil
            return BarRowData(
                segments: [
                    (String(format: "¥%.2f", c.miss), c.miss, missColor),
                    (String(format: "¥%.2f", c.hit),  c.hit,  hitColor),
                    (String(format: "¥%.2f", c.output), c.output, outputColor),
                ].filter { $0.value > 0 },
                totalLabel: total.cnyDisplay,
                extraLabel: avgCostLabel,
                modelName: model.modelName,
                displayName: pricing[model.modelName]?.displayName ?? model.modelName,
                requestCount: model.totalRequests,
                showAbove: modelIdx == 0
            )
        }
        let totalCost = rows.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.value } }
        return barSection(title: title, totalLabel: String(format: "¥%.2f", totalCost), rows: rows)
    }

    // MARK: - Token 条形图

    private func tokenSection(title: String, models: [AggregateModelUsage]) -> some View {
        let ordered = sorted(models)
        let rows: [BarRowData] = ordered.map { model in
            let miss = Double(model.totalCacheMissTokens)
            let hit  = Double(model.totalCacheHitTokens)
            let out  = Double(model.totalOutputTokens)
            let total = miss + hit + out
            let hitTotal = hit + miss
            let hitRate = hitTotal > 0 ? hit / hitTotal : 0
            let modelIdx = modelOrder.firstIndex(of: model.modelName) ?? 0
            return BarRowData(
                segments: [
                    (tokenFmt(miss), miss, missColor),
                    (tokenFmt(hit),  hit,  hitColor),
                    (tokenFmt(out),  out,  outputColor),
                ].filter { $0.value > 0 },
                totalLabel: tokenFmt(total),
                extraLabel: String(format: "缓存命中率 %.1f%%", hitRate * 100),
                modelName: model.modelName,
                displayName: pricing[model.modelName]?.displayName ?? model.modelName,
                requestCount: model.totalRequests,
                showAbove: modelIdx == 0
            )
        }
        let totalTokens = rows.reduce(0.0) { $0 + $1.segments.reduce(0) { $0 + $1.value } }
        return barSection(title: title, totalLabel: tokenFmt(totalTokens), rows: rows)
    }

    private func tokenFmt(_ n: Double) -> String {
        return String(format: "%.1fM", n / 1_000_000)
    }

    // MARK: - 通用条形图组件

    private func barSection(title: String, totalLabel: String, rows: [BarRowData]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text("合计 \(totalLabel)").font(.caption).foregroundColor(.secondary)
            }

            let maxRowTotal = rows.map { $0.segments.reduce(0) { $0 + $1.value } }.max() ?? 0
            let maxFillRatio = title.hasPrefix("今日") ? 0.76 : 0.96
            let maxTotal = maxRowTotal > 0 ? maxRowTotal / maxFillRatio : 1

            ForEach(rows.indices, id: \.self) { i in
                barRow(data: rows[i], maxTotal: maxTotal)
            }
        }
        .padding(10)
        .glassCard()
    }

    private func barRow(data: BarRowData, maxTotal: Double) -> some View {
        let modelIdx = modelOrder.firstIndex(of: data.modelName) ?? 0
        let dot = [Color.blue, Color.orange][modelIdx % 2]
        let barTotal = data.segments.reduce(0) { $0 + $1.value }

        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Circle().fill(dot).frame(width: 6, height: 6)
                    Text(data.displayName).font(.caption).fontWeight(.medium)
                }
                Text("\(data.requestCount)次").font(.system(size: 9)).foregroundColor(.secondary)
            }
            .frame(width: 62, alignment: .leading)

            GeometryReader { geo in
                let fullW = geo.size.width
                let ratio = maxTotal > 0 ? CGFloat(barTotal / maxTotal) : 0
                let minReadableW = data.segments.count > 1 ? CGFloat(56) : CGFloat(34)
                let barW = min(max(fullW * ratio, minReadableW), fullW)

                VStack(alignment: .leading, spacing: 2) {
                    if data.showAbove {
                        segmentLabelRow(segments: data.segments, barTotal: barTotal, barW: barW, fullW: fullW)
                    } else {
                        Spacer().frame(height: 13)
                    }

                    HStack(spacing: 0) {
                        ForEach(data.segments.indices, id: \.self) { j in
                            let seg = data.segments[j]
                            let segW = barTotal > 0 ? barW * CGFloat(seg.value / barTotal) : 0
                            Rectangle()
                                .fill(seg.color)
                                .frame(width: max(segW, 0), height: 18)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: fullW, alignment: .leading)

                    if !data.showAbove {
                        segmentLabelRow(segments: data.segments, barTotal: barTotal, barW: barW, fullW: fullW)
                    } else {
                        Spacer().frame(height: 13)
                    }
                }
            }
            .frame(height: 34)

            VStack(alignment: .trailing, spacing: 1) {
                Text(data.totalLabel).font(.caption).fontWeight(.bold)
                if let extra = data.extraLabel {
                    Text(extra).font(.system(size: 9)).foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(width: 118, alignment: .trailing)
        }
        .frame(height: 50)
    }

    private func segmentLabelRow(
        segments: [(label: String, value: Double, color: Color)],
        barTotal: Double,
        barW: CGFloat,
        fullW: CGFloat
    ) -> some View {
        let labelW = CGFloat(46)
        let gap = CGFloat(4)
        let labelAreaW = min(fullW, max(barW, CGFloat(segments.count) * labelW + CGFloat(max(segments.count - 1, 0)) * gap))
        let offsets = segmentLabelOffsets(
            segments: segments,
            barTotal: barTotal,
            barW: barW,
            labelAreaW: labelAreaW,
            labelW: labelW,
            gap: gap
        )

        return ZStack(alignment: .leading) {
            ForEach(segments.indices, id: \.self) { j in
                let seg = segments[j]

                Text(seg.label)
                    .font(.system(size: 10))
                    .foregroundColor(seg.color)
                    .lineLimit(1)
                    .frame(width: labelW, alignment: .center)
                    .offset(x: offsets[j])
            }
        }
        .frame(width: labelAreaW, height: 13, alignment: .leading)
    }

    private func segmentLabelOffsets(
        segments: [(label: String, value: Double, color: Color)],
        barTotal: Double,
        barW: CGFloat,
        labelAreaW: CGFloat,
        labelW: CGFloat,
        gap: CGFloat
    ) -> [CGFloat] {
        guard !segments.isEmpty else { return [] }

        let maxOffset = max(labelAreaW - labelW, 0)
        var offsets = segments.indices.map { j in
            let before = segments[..<j].reduce(0) { $0 + $1.value }
            let center = barTotal > 0 ? barW * CGFloat((before + segments[j].value / 2) / barTotal) : 0
            return min(max(center - labelW / 2, 0), maxOffset)
        }

        if offsets.count > 1 {
            for i in 1..<offsets.count {
                offsets[i] = max(offsets[i], offsets[i - 1] + labelW + gap)
            }

            if let last = offsets.indices.last, offsets[last] > maxOffset {
                offsets[last] = maxOffset
                for i in stride(from: last - 1, through: 0, by: -1) {
                    offsets[i] = min(offsets[i], offsets[i + 1] - labelW - gap)
                }
            }
        }

        return offsets.map { min(max($0, 0), maxOffset) }
    }

    // MARK: - 辅助

    private func sorted(_ models: [AggregateModelUsage]) -> [AggregateModelUsage] {
        models.sorted { a, b in
            (modelOrder.firstIndex(of: a.modelName) ?? 99) < (modelOrder.firstIndex(of: b.modelName) ?? 99)
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 40)
            Image(systemName: "snowflake").font(.largeTitle).foregroundColor(.secondary)
            Text("暂无用量数据").foregroundColor(.secondary)
            if viewModel.isRefreshing {
                ProgressView()
            } else {
                Button("刷新") { Task { await viewModel.refresh() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity).glassCard()
    }

    // MARK: - 工具栏

    private var toolbarRow: some View {
        HStack(spacing: 10) {
            if viewModel.isRefreshing {
                ProgressView().scaleEffect(0.7)
            }

            Button("刷新", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)

            if viewModel.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange).font(.caption2)
            }

            if let last = viewModel.lastRefreshTime {
                Text("更新于 \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Spacer()

            Button("登出", systemImage: "rectangle.portrait.and.arrow.right") {
                viewModel.logout()
            }
            .buttonStyle(.borderless)

            Button("设置", systemImage: "gearshape") { showSettings = true }
                .buttonStyle(.borderless)

            Divider().frame(height: 16)

            Button("退出", systemImage: "xmark.circle.fill") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless).foregroundColor(.red)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 捕获 NSWindow 引用

private struct WindowRefCapture: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { window = v.window }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window == nil { window = nsView.window }
    }
}

private struct BottomResizeHandle: NSViewRepresentable {
    @Binding var height: Double
    @Binding var savedHeight: Double
    let window: NSWindow?

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, savedHeight: $savedHeight)
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.coordinator = context.coordinator
        view.windowRef = window
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.windowRef = window
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        let height: Binding<Double>
        let savedHeight: Binding<Double>

        init(height: Binding<Double>, savedHeight: Binding<Double>) {
            self.height = height
            self.savedHeight = savedHeight
        }
    }

    final class HandleView: NSView {
        weak var windowRef: NSWindow?
        var coordinator: Coordinator?
        private var startFrame: NSRect?
        private var startMouseY: CGFloat = 0

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            startFrame = (windowRef ?? window)?.frame
            startMouseY = NSEvent.mouseLocation.y
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startFrame, let window = windowRef ?? window else { return }

            let delta = startMouseY - NSEvent.mouseLocation.y
            let newHeight = max(400, min(1200, Double(startFrame.height + delta)))
            var frame = startFrame
            frame.origin.y = startFrame.maxY - CGFloat(newHeight)
            frame.size.height = CGFloat(newHeight)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                window.setFrame(frame, display: true, animate: false)
            }

            coordinator?.height.wrappedValue = newHeight
        }

        override func mouseUp(with event: NSEvent) {
            if let height = coordinator?.height.wrappedValue {
                coordinator?.savedHeight.wrappedValue = height
            }
            startFrame = nil
        }
    }
}
