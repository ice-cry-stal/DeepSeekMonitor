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

    private let pricing = Dictionary.deepseekPricing

    private let hitColor   = Color.green
    private let missColor  = Color(red: 0.55, green: 0.85, blue: 0.55)
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
        .frame(width: 430, height: 620)
        .overlay {
            if showSettings {
                SettingsOverlay(viewModel: viewModel, isPresented: $showSettings)
            }
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
                       color: .orange)
            divider
            headerItem(label: "本月",
                       amount: viewModel.totalCost.cnyDisplay,
                       color: .blue)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .glassCard()
    }

    private func headerItem(label: String, amount: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(amount).font(.headline).fontWeight(.bold).foregroundColor(color)
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
            return BarRowData(
                segments: [
                    (String(format: "¥%.2f", c.miss), c.miss, missColor),
                    (String(format: "¥%.2f", c.hit),  c.hit,  hitColor),
                    (String(format: "¥%.2f", c.output), c.output, outputColor),
                ].filter { $0.value > 0 },
                totalLabel: total.cnyDisplay,
                extraLabel: nil,
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

            let allValues = rows.flatMap { $0.segments.map(\.value) }
            let maxTotal = allValues.max() ?? 1

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
                let fullW = geo.size.width - 80
                let ratio = maxTotal > 0 ? CGFloat(barTotal / maxTotal) : 0
                let barW = min(max(fullW * ratio, 20), fullW)

                VStack(spacing: 2) {
                    if data.showAbove {
                        HStack(spacing: 0) {
                            ForEach(data.segments.indices, id: \.self) { j in
                                let seg = data.segments[j]
                                let segW = barTotal > 0 ? barW * CGFloat(seg.value / barTotal) : 0
                                Text(seg.label).font(.system(size: 10)).foregroundColor(seg.color)
                                    .lineLimit(1).frame(width: max(segW, 28), alignment: .center)
                            }
                        }
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

                    if !data.showAbove {
                        HStack(spacing: 0) {
                            ForEach(data.segments.indices, id: \.self) { j in
                                let seg = data.segments[j]
                                let segW = barTotal > 0 ? barW * CGFloat(seg.value / barTotal) : 0
                                Text(seg.label).font(.system(size: 10)).foregroundColor(seg.color)
                                    .lineLimit(1).frame(width: max(segW, 28), alignment: .center)
                            }
                        }
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
                }
            }
            .frame(width: 66, alignment: .trailing)
        }
        .frame(height: 50)
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
