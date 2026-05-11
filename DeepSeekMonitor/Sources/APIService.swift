import Foundation
import WebKit

// MARK: - API 错误

enum APIError: LocalizedError {
    case noSession, notLoggedIn
    case httpError(Int)
    case apiError(code: Int, msg: String)
    case decodingFailed(String)
    case balanceNotFound
    case networkError(String)
    case noDataCaptured

    var errorDescription: String? {
        switch self {
        case .noSession, .notLoggedIn: return "未登录"
        case .httpError(let c):  return "HTTP \(c)"
        case .apiError(let c, let m): return "接口错误 [\(c)]: \(m)"
        case .decodingFailed(let d):  return "数据解析失败: \(d)"
        case .balanceNotFound:  return "无法获取余额信息"
        case .networkError(let d):   return "网络错误: \(d)"
        case .noDataCaptured: return "未能捕获 API 数据"
        }
    }
}

// MARK: - JS → Swift 消息

private let msgHandler = "dsCapture"

// MARK: - API Service

@MainActor
final class APIService: NSObject, @unchecked Sendable {
    static let shared = APIService()

    private let platformBase = "https://platform.deepseek.com"
    private let usageURL = "https://platform.deepseek.com/usage"

    private var webView: WKWebView?
    private var capturedResponses: [String: String] = [:]
    private var fetchContinuation: CheckedContinuation<UsageData, Error>?
    private var fetchTimeout: DispatchWorkItem?

    override private init() {
        super.init()
        _ = DeepSeekExtractionVersion.marker
        print("[API] 🟢 拦截模式就绪")
    }

    // MARK: - 设置

    func setupCookieStore(from loginWebView: WKWebView) {
        // 注入页面加载前拦截脚本
        let interceptJS = """
        (function() {
            const origFetch = window.fetch;
            window.fetch = function(...args) {
                const url = typeof args[0] === 'string' ? args[0] : args[0].url;
                return origFetch.apply(this, args).then(r => {
                    if (url.indexOf('/api/') !== -1) {
                        r.clone().text().then(body => {
                            window.webkit.messageHandlers.\(msgHandler).postMessage({url: url, body: body});
                        });
                    }
                    return r;
                });
            };
            const origOpen = XMLHttpRequest.prototype.open;
            const origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(m, url) { this._u = url; return origOpen.apply(this, arguments); };
            XMLHttpRequest.prototype.send = function() {
                const self = this;
                this.addEventListener('load', function() {
                    if (self._u && self._u.indexOf('/api/') !== -1) {
                        window.webkit.messageHandlers.\(msgHandler).postMessage({url: self._u, body: self.responseText});
                    }
                });
                return origSend.apply(this, arguments);
            };
        })();
        """

        let userScript = WKUserScript(source: interceptJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = loginWebView.configuration.websiteDataStore
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: msgHandler)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.isHidden = true

        if let window = NSApp.windows.first {
            window.contentView?.addSubview(wv)
        }

        self.webView = wv
        self.capturedResponses = [:]
        print("[API] 后台 WebView 已创建（拦截脚本已注入）")
    }

    /// 完整登出：先点击平台退出按钮，再清本地数据
    func performLogout() async {
        guard let wv = webView else {
            await clearAuth()
            return
        }

        // 导航到个人资料页（退出按钮在这里）
        if let url = URL(string: "\(platformBase)/profile") {
            wv.load(URLRequest(url: url))
            // 等待页面加载
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // 点击官方的退出按钮
            let js = """
            (function(){
                var btn = document.querySelector('.ds-button--secondary');
                if(btn && btn.textContent.includes('退出')){
                    btn.click();
                    return 'clicked';
                }
                // 备用：查找所有按钮
                var btns = document.querySelectorAll('.ds-button');
                for(var i=0; i<btns.length; i++){
                    if(btns[i].textContent.includes('退出')){
                        btns[i].click();
                        return 'clicked2';
                    }
                }
                return 'not found';
            })();
            """
            wv.evaluateJavaScript(js) { result, _ in
                print("[API] 退出按钮点击结果: \(result ?? "nil")")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        await clearAuth()
    }

    func clearAuth() async {
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: msgHandler)
        webView?.removeFromSuperview()
        webView = nil
        capturedResponses = [:]

        // 彻底清除所有 deepseek.com 相关网站数据（cookie、localStorage 等）
        let store = WKWebsiteDataStore.default()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.httpCookieStore.getAllCookies { cookies in
                let group = DispatchGroup()
                for cookie in cookies where cookie.domain.contains("deepseek.com") {
                    group.enter()
                    store.httpCookieStore.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) { cont.resume() }
            }
        }
    }

    // MARK: - 用量查询

    func fetchUsage() async throws -> UsageData {
        guard let wv = webView else { throw APIError.notLoggedIn }

        capturedResponses = [:]
        fetchTimeout?.cancel()

        return try await withCheckedThrowingContinuation { cont in
            self.fetchContinuation = cont

            // 导航到用量页面，页面加载后 React 会调 API，拦截脚本捕获响应
            if let url = URL(string: usageURL) {
                wv.load(URLRequest(url: url))
            }

            // 超时
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, let c = self.fetchContinuation else { return }
                // 超时后也用 DOM 兜底
                self.domFallback(webView: wv) { usage in
                    c.resume(returning: usage)
                    self.fetchContinuation = nil
                }
            }
            self.fetchTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
        }
    }

    // MARK: - 余额查询

    func fetchBalance() async throws -> BalanceData {
        let usage = try await fetchUsage()
        if let bal = usage.balance {
            return BalanceData(balance: bal, currency: usage.currency ?? "CNY")
        }
        throw APIError.balanceNotFound
    }

    // MARK: - 处理捕获的 API 响应

    private func processCapturedResponses() {
        var rawUsageData: RawUsageBizData?
        var balance: Double?
        var currency: String?

        for (url, body) in capturedResponses {
            guard let data = body.data(using: .utf8) else { continue }
            print("[API] 处理捕获响应: \(url) (\(body.count) 字节)")

            // 解析用量金额端点
            if url.contains("usage/amount") || url.contains("usage_amount") {
                if let decoded = try? JSONDecoder().decode(RawBizResponse<RawUsageBizData>.self, from: data),
                   decoded.code == 0,
                   let bizData = decoded.data?.biz_data {
                    rawUsageData = bizData
                    print("[API] ✅ 用量数据已解析: \(bizData.total?.count ?? 0) 个模型, \(bizData.days?.count ?? 0) 天")
                } else {
                    print("[API] ⚠️ 用量数据解析失败")
                }
            }

            // 解析用户摘要端点（余额）
            if url.contains("users/get_user_summary") {
                if let decoded = try? JSONDecoder().decode(RawBizResponse<RawUserSummaryBizData>.self, from: data),
                   decoded.code == 0,
                   let bizData = decoded.data?.biz_data {
                    balance = bizData.extractBalance()
                    currency = bizData.extractCurrency()
                    print("[API] ✅ 余额已解析: \(balance?.cnyDisplay ?? "--")")
                } else {
                    print("[API] ⚠️ 余额解析失败")
                }
            }
        }

        // 如果成功解析了用量数据，构建 UsageData 并返回
        if let raw = rawUsageData, let c = fetchContinuation {
            let usage = raw.toUsageData(balance: balance, currency: currency)
            c.resume(returning: usage)
            fetchContinuation = nil
            fetchTimeout?.cancel()
            print("[API] 🎉 数据提取完成，已返回给 ViewModel")
            return
        }

        // 如果没有捕获到用量数据但可能是还没加载完，给一次重试
        if !capturedResponses.isEmpty && rawUsageData == nil {
            print("[API] ⏳ 有响应但未解析到用量，3 秒后重试...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.fetchContinuation != nil else { return }
                self.processCapturedResponses() // 重试
            }
        }
    }

    // MARK: - DOM 兜底

    private func domFallback(webView: WKWebView, completion: @escaping (UsageData) -> Void) {
        let js = """
        (function() {
            var text = document.body ? document.body.innerText : '';
            var result = {balance: null, models: []};

            // 提取金额：查找 ¥ 或 CNY 附近的数字
            var amounts = [];
            var re = /¥\\s*([\\d,]+\\.?\\d{1,2})(?!\\d)/g;
            var m;
            while ((m = re.exec(text)) !== null) {
                amounts.push(parseFloat(m[1].replace(/,/g, '')));
            }
            // 也搜 CNY
            var re2 = /([\\d,]+\\.?\\d{1,2})\\s*CNY/g;
            while ((m = re2.exec(text)) !== null) {
                amounts.push(parseFloat(m[1].replace(/,/g, '')));
            }
            if (amounts.length >= 2) {
                amounts.sort(function(a,b){return b-a;});
                result.balance = amounts[0];
            }

            // 提取模型：deepseek- 开头的行
            var lines = text.split('\\n');
            for (var i = 0; i < lines.length; i++) {
                var l = lines[i].trim();
                if (/^deepseek-/.test(l)) {
                    var model = {modelName: l, requestCount: 0, totalTokens: 0};
                    for (var j = i+1; j < Math.min(i+10, lines.length) && (!model.requestCount || !model.totalTokens); j++) {
                        var nl = lines[j];
                        var rc = nl.match(/(\\d[\\d,]*)\\s*(?:次|请求)/);
                        if (rc && !model.requestCount) model.requestCount = parseInt(rc[1].replace(/,/g, ''));
                        var tc = nl.match(/(\\d[\\d,]+)\\s*Token/i);
                        if (tc && !model.totalTokens) model.totalTokens = parseInt(tc[1].replace(/,/g, ''));
                    }
                    if (model.requestCount > 0 || model.totalTokens > 0) models.push(model);
                }
            }
            result.models = models;

            // 完整 pageText 保存调试
            result.pageText = text.substring(0, 3000);
            return JSON.stringify(result);
        })();
        """

        webView.evaluateJavaScript(js) { result, error in
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                completion(UsageData(dailyUsages: nil, total: nil, balance: nil, currency: "CNY"))
                return
            }

            var models: [DailyUsage] = []
            if let ml = dict["models"] as? [[String: Any]] {
                for m in ml {
                    models.append(DailyUsage(date: self.dateStr(), models: [
                        ModelUsageEntry(
                            modelName: m["modelName"] as? String ?? "",
                            cacheHitTokens: 0,
                            cacheMissTokens: Int64(m["totalTokens"] as? Int ?? 0),
                            outputTokens: 0,
                            requestCount: m["requestCount"] as? Int ?? 0
                        )
                    ]))
                }
            }

            let usage = UsageData(
                dailyUsages: models.isEmpty ? nil : models,
                total: nil,
                balance: dict["balance"] as? Double,
                currency: "CNY"
            )
            completion(usage)
        }
    }

    // MARK: - 工具方法

    private func extractBalance(from json: [String: Any]) -> (Double, String)? {
        for key in ["balance", "total_balance", "amount"] {
            if let d = json[key] as? Double { return (d, findCur(in: json)) }
            if let s = json[key] as? String, let d = Double(s) { return (d, findCur(in: json)) }
        }
        if let data = json["data"] as? [String: Any], let r = extractBalance(from: data) { return r }
        return nil
    }

    private func findCur(in json: [String: Any]) -> String {
        if let v = json["currency"] as? String { return v }
        return "CNY"
    }

    private func dateStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func verifySession() async -> Bool {
        do { _ = try await fetchUsage(); return true }
        catch { return false }
    }
}

// MARK: - WKNavigationDelegate

extension APIService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            print("[API] 页面加载完成: \(webView.url?.absoluteString ?? "?")")
            // 页面加载完成后，React 会发起 API 请求
            // 等待几秒让 API 响应被捕获
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.processCapturedResponses()
            }
        }
    }
}

// MARK: - WKScriptMessageHandler

extension APIService: WKScriptMessageHandler {
    nonisolated func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard message.name == msgHandler,
                  let dict = message.body as? [String: Any],
                  let url = dict["url"] as? String,
                  let body = dict["body"] as? String else { return }
            self.capturedResponses[url] = body
            print("[API] 📡 捕获: \(url) (\(body.count) 字节)")
        }
    }
}
