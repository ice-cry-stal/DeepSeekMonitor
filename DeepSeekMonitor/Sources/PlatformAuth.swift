import SwiftUI
import WebKit
import Security

// MARK: - Keychain

enum KeychainHelper {
    private static let service = "com.deepseek.monitor"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - 认证信息

struct PlatformAuthInfo {
    let cookieString: String
}

// MARK: - 登录 View

struct LoginView: View {
    let onLoginSuccess: (PlatformAuthInfo) -> Void

    @State private var webView: WKWebView?
    @State private var showContinueButton = false
    @State private var isExtracting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.badge.key.fill")
                    .foregroundColor(.blue)
                Text("登录 DeepSeek 平台")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .padding(.top, 4)

            Text("登录后点击底部按钮，自动抓取页面数据")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 4)

            ZStack(alignment: .top) {
                WebViewWrapper(webView: $webView)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                if isExtracting {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            VStack(spacing: 6) {
                if showContinueButton {
                    Button(action: saveSession) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("我已登录，进入仪表盘")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isExtracting)
                } else {
                    ProgressView().scaleEffect(0.6)
                    Text("等待登录…").font(.caption2).foregroundColor(.secondary)
                }

                Button("退出应用", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain).font(.caption).foregroundColor(.red.opacity(0.6)).padding(.top, 2)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .glassBackground(blendingMode: .withinWindow)
        .frame(width: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showContinueButton = true
            }
        }
    }

    private func saveSession() {
        guard let webView = webView else { return }
        isExtracting = true

        // 保存 cookies 到 Keychain，然后进仪表盘
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let cookieStr = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            KeychainHelper.save(key: "deepseek_session", value: cookieStr)

            // 也共享 cookie store
            Task { @MainActor in
                APIService.shared.setupCookieStore(from: webView)
            }

            DispatchQueue.main.async {
                isExtracting = false
                onLoginSuccess(PlatformAuthInfo(cookieString: cookieStr))
            }
        }
    }
}

// MARK: - WKWebView 包装器

struct WebViewWrapper: NSViewRepresentable {
    @Binding var webView: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        if let url = URL(string: "https://platform.deepseek.com") {
            wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
        DispatchQueue.main.async { self.webView = wv }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, WKNavigationDelegate {}
}
