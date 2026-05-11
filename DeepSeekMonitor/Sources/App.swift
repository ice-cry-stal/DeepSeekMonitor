import SwiftUI
import AppKit

// MARK: - 应用入口

@main
struct DeepSeekMonitorApp: App {
    @State private var viewModel = ViewModel()

    init() {
        UserDefaults.standard.register(defaults: [
            "menu_display_mode": 0
        ])
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                switch viewModel.authState {
                case .unknown:
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(0.8)
                        Text("检查登录状态…").font(.caption).foregroundColor(.secondary)
                        Button("退出应用", role: .destructive) {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.plain).font(.caption2).foregroundColor(.red.opacity(0.6))
                        .keyboardShortcut("q", modifiers: .command)
                    }
                    .padding().frame(width: 200, height: 110)
                    .glassBackground(blendingMode: .withinWindow)

                case .loggedOut:
                    LoginView { info in viewModel.onLoginSuccess(authInfo: info) }

                case .loggedIn:
                    DashboardView(viewModel: viewModel)
                }
            }
            .environment(viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    let viewModel: ViewModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalSettings
                    .tabItem {
                        Label("通用", systemImage: "gearshape")
                    }

                aboutView
                    .tabItem {
                        Label("关于", systemImage: "info.circle")
                    }
            }

            Divider()
            HStack {
                Spacer()
                Button("关闭") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 360, height: 420)
    }

    // MARK: - 通用设置

    private var generalSettings: some View {
        Form {
            Section("登录状态") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loginStatusText)
                            .font(.body)
                        Text(loginStatusDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            Section("菜单栏显示") {
                HStack(spacing: 8) {
                    ForEach([(0, "冰晶"), (1, "剩余"), (2, "今日"), (3, "本月")], id: \.0) { mode, label in
                        Button(label) {
                            viewModel.menuDisplayMode = mode
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.menuDisplayMode == mode ? .blue : .secondary)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)

                Text("修改后请点击下方「立即刷新」生效")
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Section("数据刷新") {
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    Text("6 分钟")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("已刷新")
                    Spacer()
                    Text("\(viewModel.refreshCount) 次")
                        .foregroundColor(.secondary)
                }
                if let last = viewModel.lastRefreshTime {
                    HStack {
                        Text("上次刷新")
                        Spacer()
                        Text(last.formatted(date: .abbreviated, time: .standard))
                            .foregroundColor(.secondary)
                    }
                }

                Button("立即刷新") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isRefreshing)
            }

            Section {
                Button("退出应用 (⌘Q)", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 关于

    private var aboutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.system(size: 32))
                .foregroundColor(.blue)

            Text("DeepSeek Monitor")
                .font(.title2)
                .fontWeight(.bold)

            Text("v1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Made with ❤️ by IceCryStal")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("macOS 菜单栏 DeepSeek 平台用量监控工具")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("数据来源: platform.deepseek.com")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("每 6 分钟自动刷新一次（官方数据延迟约 5 分钟）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 辅助

    private var loginStatusText: String {
        switch viewModel.authState {
        case .unknown:  return "检查中…"
        case .loggedOut: return "未登录"
        case .loggedIn:  return "已登录"
        }
    }

    private var loginStatusDetail: String {
        switch viewModel.authState {
        case .unknown:  return ""
        case .loggedOut: return "请通过菜单栏登录 DeepSeek 平台"
        case .loggedIn:  return "使用平台 session cookie 鉴权"
        }
    }
}

// MARK: - 菜单栏标签

struct MenuBarLabel: View {
    let viewModel: ViewModel

    private func short(_ d: Double) -> String {
        String(format: "%.2f", d)
    }

    var body: some View {
        switch viewModel.menuDisplayMode {
        case 1:
            if let bal = viewModel.remainingBalance {
                Text("余\(short(bal))").font(.system(size: 12, weight: .medium))
            } else {
                Image(systemName: viewModel.menuIconName).font(.system(size: 14))
            }
        case 2:
            Text("今\(short(viewModel.todayCost))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)
        case 3:
            Text("月\(short(viewModel.totalCost))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
        default:
            Image(systemName: viewModel.menuIconName)
                .font(.system(size: 14))
        }
    }
}

// MARK: - 设置浮层（替代 sheet）

struct SettingsOverlay: View {
    let viewModel: ViewModel
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture { isPresented = false }

            SettingsView(viewModel: viewModel) {
                isPresented = false
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
}
