import Foundation

// MARK: - 通用 API 响应结构（旧格式，保留兼容）

/// DeepSeek 平台统一响应格式（旧）
struct APIResponse<T: Codable>: Codable {
    let code: Int
    let msg: String?
    let data: T?
}

// MARK: - 用量 API（App 内部模型，供 UI 使用）

typealias UsageResponse = APIResponse<UsageData>

struct UsageData: Codable {
    let dailyUsages: [DailyUsage]?
    let total: TotalUsage?
    let balance: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case dailyUsages = "daily_usages"
        case total
        case balance
        case currency
    }
}

struct DailyUsage: Codable, Identifiable {
    let date: String
    let models: [ModelUsageEntry]

    var id: String { date }
}

struct ModelUsageEntry: Codable, Identifiable {
    let modelName: String
    let cacheHitTokens: Int64
    let cacheMissTokens: Int64
    let outputTokens: Int64
    let requestCount: Int

    var id: String { modelName }

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case cacheHitTokens = "cache_hit_tokens"
        case cacheMissTokens = "cache_miss_tokens"
        case outputTokens = "output_tokens"
        case requestCount = "request_count"
    }
}

struct TotalUsage: Codable {
    let totalRequests: Int?
    let totalCacheHitTokens: Int64?
    let totalCacheMissTokens: Int64?
    let totalOutputTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case totalCacheHitTokens = "total_cache_hit_tokens"
        case totalCacheMissTokens = "total_cache_miss_tokens"
        case totalOutputTokens = "total_output_tokens"
    }
}

// MARK: - 余额 API

typealias BalanceResponse = APIResponse<BalanceData>

struct BalanceData: Codable {
    let balance: Double
    let currency: String
}

// MARK: - 用量汇总

struct AggregateModelUsage: Identifiable {
    let modelName: String
    let totalCacheHitTokens: Int64
    let totalCacheMissTokens: Int64
    let totalOutputTokens: Int64
    let totalRequests: Int

    var id: String { modelName }

    var totalTokens: Int64 {
        totalCacheHitTokens + totalCacheMissTokens + totalOutputTokens
    }
}

// MARK: - 图表数据

struct ChartDataPoint: Identifiable {
    let model: String
    let type: TokenType
    let value: Int64

    var id: String { "\(model)-\(type.rawValue)" }
}

// MARK: - Token 类型

enum TokenType: String, CaseIterable {
    case cacheHit = "缓存命中"
    case cacheMiss = "缓存未命中"
    case output = "输出"

    var hexColor: String {
        switch self {
        case .cacheHit:  return "34C759"
        case .cacheMiss: return "FF9500"
        case .output:    return "007AFF"
        }
    }
}

// MARK: - 定价模型

struct ModelPricing {
    let displayName: String
    let cacheHitPerMillion: Double
    let cacheMissPerMillion: Double
    let outputPerMillion: Double

    func cost(cacheHit: Int64, cacheMiss: Int64, output: Int64) -> Double {
        let hit   = Double(cacheHit) / 1_000_000 * cacheHitPerMillion
        let miss  = Double(cacheMiss) / 1_000_000 * cacheMissPerMillion
        let out   = Double(output) / 1_000_000 * outputPerMillion
        return hit + miss + out
    }
}

extension Dictionary where Key == String, Value == ModelPricing {
    static let deepseekPricing: [String: ModelPricing] = [
        "deepseek-v4-flash": ModelPricing(
            displayName: "V4Flash",
            cacheHitPerMillion: 0.02,
            cacheMissPerMillion: 1.0,
            outputPerMillion: 2.0
        ),
        "deepseek-v4-pro": ModelPricing(
            displayName: "V4Pro",
            cacheHitPerMillion: 0.025,
            cacheMissPerMillion: 3.0,
            outputPerMillion: 6.0
        ),
    ]
}

// MARK: - 饼图数据

struct PieSliceData: Identifiable {
    let modelName: String
    let displayName: String
    let totalTokens: Int64
    let cost: Double
    let percentage: Double

    var id: String { modelName }

    /// 统一用 K/M 显示，保留两位小数
    var tokensDisplay: String {
        let k = Double(totalTokens) / 1000.0
        if k >= 1000 {
            return String(format: "%.2fM", k / 1000.0)
        }
        return String(format: "%.2fK", k)
    }

    var percentDisplay: String {
        String(format: "%.0f%%", percentage * 100)
    }

    var costDisplay: String {
        String(format: "¥%.2f元", cost)
    }
}

// MARK: - 辅助

extension Int64 {
    var tokenDisplay: String {
        let absValue = Double(self)
        switch absValue {
        case 1_000_000...:
            return String(format: "%.1fM", absValue / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", absValue / 1_000)
        default:
            return "\(self)"
        }
    }
}

extension Double {
    var cnyDisplay: String {
        return String(format: "¥%.2f", self)
    }
}

// MARK: - ===== 原始 API 响应模型（匹配实际 JSON 格式）=====

/// 真实 API 响应格式：
/// { "code": 0, "msg": "", "data": { "biz_code": 0, "biz_msg": "", "biz_data": {...} } }
struct RawBizResponse<T: Codable>: Codable {
    let code: Int
    let msg: String?
    let data: RawBizWrapper<T>?
}

struct RawBizWrapper<T: Codable>: Codable {
    let biz_code: Int?
    let biz_msg: String?
    let biz_data: T?
}

// MARK: - 用量金额端点 (api/v0/usage/amount)

/// biz_data 结构：{ "total": [...], "days": [...] }
struct RawUsageBizData: Codable {
    let total: [RawUsageModel]?
    let days: [RawUsageDay]?
}

struct RawUsageModel: Codable {
    let model: String
    let usage: [RawUsageEntry]
}

struct RawUsageEntry: Codable {
    /// PROMPT_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN / RESPONSE_TOKEN / REQUEST
    let type: String
    /// 字符串形式的数量（整数 Token 数）
    let amount: String
}

struct RawUsageDay: Codable {
    let date: String
    let data: [RawUsageModel]
}

// MARK: - 用户摘要端点 (api/v0/users/get_user_summary)

/// biz_data 结构：包含 normal_wallets、monthly_costs 等
struct RawUserSummaryBizData: Codable {
    let normal_wallets: [RawWallet]?
    let monthly_costs: [RawMonthlyCost]?
    let monthly_token_usage: String?
    let current_token: Int?
}

struct RawWallet: Codable {
    let currency: String?
    let balance: String?
}

struct RawMonthlyCost: Codable {
    let currency: String?
    let amount: String?
}

// MARK: - Raw → App 模型转换

extension RawUsageBizData {

    /// 将原始 API 用量数据转换为 App 内部模型
    func toUsageData(balance: Double?, currency: String?) -> UsageData {
        // 过滤掉 "deepseek-chat & deepseek-reasoner"（全为零的虚拟条目）
        let dailyUsages: [DailyUsage]? = days?.compactMap { day in
            let models = day.data
                .filter { $0.model != "deepseek-chat & deepseek-reasoner" }
                .compactMap { $0.toModelUsageEntry() }
            guard !models.isEmpty else { return nil }
            return DailyUsage(date: day.date, models: models)
        }

        // 从 total 构建总览
        let totalModels = self.total?
            .filter { $0.model != "deepseek-chat & deepseek-reasoner" }
            .compactMap { $0.toModelUsageEntry() }
            ?? []

        let total: TotalUsage? = {
            guard !totalModels.isEmpty else { return nil }
            return TotalUsage(
                totalRequests: totalModels.reduce(0) { $0 + $1.requestCount },
                totalCacheHitTokens: totalModels.reduce(0) { $0 + $1.cacheHitTokens },
                totalCacheMissTokens: totalModels.reduce(0) { $0 + $1.cacheMissTokens },
                totalOutputTokens: totalModels.reduce(0) { $0 + $1.outputTokens }
            )
        }()

        return UsageData(
            dailyUsages: dailyUsages,
            total: total,
            balance: balance,
            currency: currency
        )
    }
}

extension RawUsageModel {

    /// 将单条模型的 API 用量转换为 ModelUsageEntry
    /// 如果所有 Token 和请求数均为 0 则返回 nil（跳过空模型）
    func toModelUsageEntry() -> ModelUsageEntry? {
        var cacheHit: Int64 = 0
        var cacheMiss: Int64 = 0
        var output: Int64 = 0
        var requests: Int = 0

        for entry in usage {
            switch entry.type {
            case "PROMPT_CACHE_HIT_TOKEN":
                cacheHit = Int64(entry.amount) ?? 0
            case "PROMPT_CACHE_MISS_TOKEN":
                cacheMiss = Int64(entry.amount) ?? 0
            case "RESPONSE_TOKEN":
                output = Int64(entry.amount) ?? 0
            case "REQUEST":
                requests = Int(entry.amount) ?? 0
            default:
                break // PROMPT_TOKEN（始终为 0，忽略）
            }
        }

        // 跳过全零模型
        guard cacheHit > 0 || cacheMiss > 0 || output > 0 || requests > 0 else {
            return nil
        }

        return ModelUsageEntry(
            modelName: model,
            cacheHitTokens: cacheHit,
            cacheMissTokens: cacheMiss,
            outputTokens: output,
            requestCount: requests
        )
    }
}

extension RawUserSummaryBizData {

    /// 从用户摘要中提取余额（元）
    func extractBalance() -> Double? {
        guard let wallet = normal_wallets?.first,
              let balanceStr = wallet.balance,
              let balance = Double(balanceStr) else {
            return nil
        }
        return balance
    }

    /// 提取货币类型
    func extractCurrency() -> String {
        return normal_wallets?.first?.currency ?? "CNY"
    }
}
