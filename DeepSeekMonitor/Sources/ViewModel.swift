import SwiftUI
import Observation
import WebKit

// MARK: - 应用状态

@MainActor
@Observable
final class ViewModel {

    enum AuthState {
        case unknown
        case loggedOut
        case loggedIn
    }

    private(set) var authState: AuthState = .unknown

    private(set) var usageData: UsageData?
    private(set) var balance: Double?
    private(set) var currency: String = "CNY"
    private(set) var isRefreshing = false
    private(set) var lastRefreshTime: Date?
    private(set) var errorMessage: String?
    private(set) var refreshCount: Int = 0
    private(set) var aggregateUsage: [AggregateModelUsage] = []

    let refreshInterval: TimeInterval = 360

    private let apiService = APIService.shared
    private var timer: Timer?

    init() {
        menuDisplayMode = UserDefaults.standard.integer(forKey: "menu_display_mode")
        restoreSession()
    }

    // MARK: - 恢复登录

    private func restoreSession() {
        guard let cookieStr = KeychainHelper.load(key: "deepseek_session"),
              !cookieStr.isEmpty else {
            authState = .loggedOut
            return
        }

        Task {
            // 创建后台 WebView 并注入之前保存的 cookie
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            let restoreWV = WKWebView(frame: .zero, configuration: config)

            let pairs = cookieStr.components(separatedBy: "; ")
            for pair in pairs {
                let parts = pair.components(separatedBy: "=")
                if parts.count >= 2 {
                    let name = parts[0]
                    let value = parts.dropFirst().joined(separator: "=")
                    if let cookie = HTTPCookie(properties: [
                        .domain: ".deepseek.com",
                        .path: "/",
                        .name: name,
                        .value: value,
                        .secure: "TRUE",
                        .expires: NSDate(timeIntervalSinceNow: 86400 * 30),
                    ]) {
                        await config.websiteDataStore.httpCookieStore.setCookie(cookie)
                    }
                }
            }

            // 等待 cookie 设置完成
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let window = NSApp.windows.first {
                window.contentView?.addSubview(restoreWV)
            }

            // 共享 cookie store 给后台 WebView
            apiService.setupCookieStore(from: restoreWV)

            // 验证：尝试提取页面数据
            do {
                _ = try await apiService.fetchUsage()
                authState = .loggedIn
                startPolling()
                await refresh()
            } catch {
                print("[ViewModel] 恢复 session 失败: \(error)")
                KeychainHelper.delete(key: "deepseek_session")
                restoreWV.removeFromSuperview()
                authState = .loggedOut
            }
        }
    }

    // MARK: - 登录

    func onLoginSuccess(authInfo: PlatformAuthInfo) {
        KeychainHelper.save(key: "deepseek_session", value: authInfo.cookieString)
        // setupCookieStore 已在 LoginView 中调用
        authState = .loggedIn
        startPolling()
        Task { await refresh() }
    }

    func logout() {
        timer?.invalidate()
        timer = nil
        KeychainHelper.delete(key: "deepseek_session")
        usageData = nil
        balance = nil
        aggregateUsage = []
        errorMessage = nil
        refreshCount = 0
        authState = .loggedOut

        Task {
            await apiService.performLogout()
        }
    }

    // MARK: - 定时刷新

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard authState == .loggedIn else { return }
        isRefreshing = true
        errorMessage = nil
        refreshCount += 1

        do {
            // fetchUsage 会导航 WebView 到用量页面，注入 JS 提取 DOM 数据
            // 余额和用量一起提取，不需要单独查询
            let usage = try await apiService.fetchUsage()
            self.usageData = usage
            self.aggregateUsage = Self.aggregateByModel(dailyUsages: usage.dailyUsages ?? [])

            if let bal = usage.balance {
                self.balance = bal
                self.currency = usage.currency ?? "CNY"
            }

            self.lastRefreshTime = Date()
        } catch {
            self.errorMessage = error.localizedDescription
            print("[ViewModel] 刷新失败: \(error)")
            // 如果连续失败可能是 cookie 过期，标记为需重新登录
        }

        isRefreshing = false
    }

    // MARK: - 聚合

    private static func aggregateByModel(dailyUsages: [DailyUsage]) -> [AggregateModelUsage] {
        var map: [String: (hit: Int64, miss: Int64, out: Int64, req: Int)] = [:]
        for d in dailyUsages {
            for e in d.models {
                let c = map[e.modelName] ?? (0, 0, 0, 0)
                map[e.modelName] = (c.hit + e.cacheHitTokens, c.miss + e.cacheMissTokens, c.out + e.outputTokens, c.req + e.requestCount)
            }
        }
        return map.map { k, v in
            AggregateModelUsage(modelName: k, totalCacheHitTokens: v.hit, totalCacheMissTokens: v.miss, totalOutputTokens: v.out, totalRequests: v.req)
        }
    }

    // MARK: - 费用

    func costFor(model: AggregateModelUsage) -> Double {
        guard let p = Dictionary.deepseekPricing[model.modelName] else { return 0 }
        return p.cost(cacheHit: model.totalCacheHitTokens, cacheMiss: model.totalCacheMissTokens, output: model.totalOutputTokens)
    }
    var totalCost: Double { aggregateUsage.reduce(0) { $0 + costFor(model: $1) } }

    /// 单项费用拆解
    func costBreakdown(model: AggregateModelUsage) -> (hit: Double, miss: Double, output: Double) {
        guard let p = Dictionary.deepseekPricing[model.modelName] else { return (0, 0, 0) }
        return (
            Double(model.totalCacheHitTokens) / 1_000_000 * p.cacheHitPerMillion,
            Double(model.totalCacheMissTokens) / 1_000_000 * p.cacheMissPerMillion,
            Double(model.totalOutputTokens) / 1_000_000 * p.outputPerMillion
        )
    }

    // MARK: - 今日 / 本月数据

    private func todayDateStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 今日按模型聚合
    var todayAggregateUsage: [AggregateModelUsage] {
        let today = todayDateStr()
        let todayUsages = usageData?.dailyUsages?.filter { $0.date == today } ?? []
        return Self.aggregateByModel(dailyUsages: todayUsages)
    }

    /// 今日饼图数据
    var todayPieSlices: [PieSliceData] {
        let aggregated = todayAggregateUsage
        let total = aggregated.reduce(0) { $0 + $1.totalTokens }
        guard total > 0 else { return [] }
        return aggregated.map { model in
            PieSliceData(
                modelName: model.modelName,
                displayName: Dictionary.deepseekPricing[model.modelName]?.displayName ?? model.modelName,
                totalTokens: model.totalTokens,
                cost: costFor(model: model),
                percentage: Double(model.totalTokens) / Double(total)
            )
        }
    }

    /// 本月饼图数据
    var monthPieSlices: [PieSliceData] {
        let total = aggregateUsage.reduce(0) { $0 + $1.totalTokens }
        guard total > 0 else { return [] }
        return aggregateUsage.map { model in
            PieSliceData(
                modelName: model.modelName,
                displayName: Dictionary.deepseekPricing[model.modelName]?.displayName ?? model.modelName,
                totalTokens: model.totalTokens,
                cost: costFor(model: model),
                percentage: Double(model.totalTokens) / Double(total)
            )
        }
    }

    /// 今日总花费
    var todayCost: Double {
        todayPieSlices.reduce(0) { $0 + $1.cost }
    }

    /// 账户剩余余额
    var remainingBalance: Double? { balance }

    // MARK: - 菜单栏显示（4 选 1）

    var menuDisplayMode: Int = 0 {
        didSet { UserDefaults.standard.set(menuDisplayMode, forKey: "menu_display_mode") }
    }

    // MARK: - UI

    var menuIconName: String {
        guard authState == .loggedIn else { return "snowflake" }
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if errorMessage != nil { return "exclamationmark.triangle" }
        return "snowflake"
    }
}
