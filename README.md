<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-snowflake?logo=apple&color=8BC34A" alt="platform">
  <img src="https://img.shields.io/badge/swift-6.0%2B-FA7343?logo=swift" alt="swift">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="license">
</p>

<h1 align="center">❄️ DeepSeek Monitor</h1>
<p align="center"><i>macOS 菜单栏的 DeepSeek API 用量仪表盘</i></p>

<p align="center">
  <img src="https://img.shields.io/badge/余-10.41-34C759?style=flat-square">
  <img src="https://img.shields.io/badge/今-5.36-FF9500?style=flat-square">
  <img src="https://img.shields.io/badge/月-10.00-007AFF?style=flat-square">
</p>

---

## 最新设计思路

这版界面的核心，不是“展示更多数据”，而是“让人更快看懂差异”。

### 视觉优先级

- 左侧负责识别对象：模型名、请求次数
- 中间负责比较：柱状图本体
- 右侧负责确认：总量、命中率、平均花费

### 今日和本月分开处理

- 今日模块沿用当前的本月长度，避免被压得过短
- 本月模块继续向右延伸，尽量贴近右侧标线，用来体现模型之间的长期差异
- 两类模块不共用同一套缩放策略

### 标签规则

- 分段标签按柱子的中心位置摆放
- 标签之间会做避让，避免数字糊在一起
- 如果空间不足，优先保证可读性，其次才是严格对齐

### 平均花费规则

- 只有当某个模型的 Token 总消耗达到 `30M` 时，才显示“每亿 Token 平均花费”
- 这个规则对“今日费用构成”和“本月费用构成”都生效
- 平均花费采用两行展示，减少文字挤压

### 数据边界

- 不依赖 API Key
- 登录态保存在本机 Keychain
- 仓库只保留源码和必要配置，不提交编译产物

## ✨ 功能

- 🧊 **菜单栏常驻** — 冰晶图标停靠右上角，点开即见仪表盘
- 💰 **实时账单** — 剩余余额、今日花费、本月花费一目了然
- 📊 **堆叠条形图** — 费用 + Token 消耗，今日 vs 本月对比
- 🧩 **按模型拆分** — V4Flash / V4Pro 各自独立展示
- 🎯 **缓存命中率** — 精确到百分比，优化 Prompt 有据可依
- 🧮 **平均花费** — Token 达到 `30M` 时显示每亿 Token 平均花费
- 🔄 **6 分钟自动刷新** — 官方数据延迟约 5 分钟，刚好赶上
- 🎛 **菜单栏自定义** — 图标 / 余额 / 今日 / 本月，4 选 1 显示

## 🖥 界面

```
剩余 ¥10.41       今日 ¥5.36       本月 ¥10.00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
■ 缓存未命中  ■ 缓存命中  ■ 输出

今日费用构成                          合计 ¥5.36
  ● V4Flash  [████¥0.94██¥0.42█¥0.53]     ¥1.89
  ● V4Pro    [███████¥3.83█¥0.54██¥3.72]  ¥3.47

今日 Token 消耗                       合计 40.1M
  ● V4Flash  [█0.9M██21.1M█0.3M]  22.3M  缓存命中率 95.8%
  ● V4Pro    [█0.9M█22.3M█0.4M]    23.3M  缓存命中率 95.9%
```

## ⚡ 快速开始

```bash
bash build.sh
```

> 需要 macOS 14+ 和 Swift 6.0（Command Line Tools 自带）

首次运行需登录 [platform.deepseek.com](https://platform.deepseek.com)，之后自动保持 session。

## 📦 发布

如果要给别人下载使用，建议把编译好的 `.app` 打成 `.zip` 或 `.dmg`，作为 GitHub Releases 的附件发布。这样别人可以直接下载，不需要拉源码自己编译。

## 🏗 项目结构

```
Sources/
├── App.swift              # MenuBarExtra 入口
├── APIService.swift       # 网页抓取 + API 拦截解析
├── DashboardView.swift    # 仪表盘 UI（堆叠条形图）
├── GlassBackground.swift  # 毛玻璃特效
├── Models.swift           # 数据模型 + DeepSeek 定价
├── PlatformAuth.swift     # 登录 + Keychain
└── ViewModel.swift        # 状态管理
```

## 🔐 原理

不依赖 API Key。通过 WKUserScript 注入拦截 `window.fetch`，在已登录的 WebView 中捕获平台自身的 API 响应，直接解析用量数据。

所有数据仅存储在本地 **Keychain** 和 **UserDefaults**，不上传任何第三方。

## ⚠️ 已知问题

| 问题 | 说明 |
|------|------|
| 右侧数据列在窄窗口下仍可能挤压 | 平均花费和命中率都保留两行展示，极窄高度下仍会压缩右列空间 |
| 拖拽调整窗口有轻微闪动 | 现在改成原生鼠标拖拽计算，问题已明显缓解，但不同 macOS 版本上仍可能有细微抖动 |
| 标签截断（极小值） | 已通过碰撞避让和最小宽度缓解，极端小值仍可能被缩短 |

## 📝 改动记录（相对原版）

| 改动 | 文件 |
|------|------|
| 窗口高度拖拽 + 记忆 | DashboardView.swift |
| 今日/本月不同缩放策略 | DashboardView.swift |
| 分段标签碰撞避让 | DashboardView.swift |
| 平均花费 >=30M Token 触发显示 | DashboardView.swift |
| missColor 加深 (0.55,0.85,0.55)→(0.4,0.75,0.4) | DashboardView.swift |
| "每日8:00更新" 提示 | DashboardView.swift |
| 段标签 minWidth 28→38 防截断 | DashboardView.swift |
| UTC/北京时间对齐 | ViewModel.swift, APIService.swift |
| 双重 resume 崩溃保护 `takeContinuation()` | APIService.swift |
| WebView 泄漏修复 | ViewModel.swift |
| 重试超时报错 `APIError.noDataCaptured` | APIService.swift |
| 休眠/唤醒自动刷新 | ViewModel.swift |
| onLoginSuccess 补 observers | ViewModel.swift |
| 删除 VersionMark.swift | — |

## 📄 License

MIT © IceCryStal

---

<p align="center"><sub>Made with ❤️ by IceCryStal</sub></p>
