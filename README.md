[README.md](https://github.com/user-attachments/files/27601026/README.md)
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
用calude code 桌面版写出来的东西，别问我代码，我不懂-。-

## ✨ 功能

- 🧊 **菜单栏常驻** — 冰晶图标停靠右上角，点开即见仪表盘
- 💰 **实时账单** — 剩余余额、今日花费、本月花费一目了然
- 📊 **堆叠条形图** — 费用 + Token 消耗，今日 vs 本月对比
- 🧩 **按模型拆分** — V4Flash / V4Pro 各自独立展示（我只选了截取这两个模型的数据）
- 🎯 **缓存命中率** — 精确到百分比，优化 Prompt 有据可依
- 🔄 **6 分钟自动刷新** — 官方数据延迟约 5 分钟，刚好赶上
- 🎛 **菜单栏自定义** — 图标 / 余额 / 今日 / 本月，4 选 1 显示

## 🖥 界面

<img width="147" height="112" alt="image" src="https://github.com/user-attachments/assets/26a32279-a386-49c0-8421-7661486338ed" />

<img width="430" height="879" alt="image" src="https://github.com/user-attachments/assets/c0f56010-98db-438e-9909-d99141aa4c67" />

## ⚡ 快速开始

```bash
git clone https://github.com/IceCryStal/DeepSeekMonitor.git
cd DeepSeekMonitor
bash build.sh
```

> 需要 macOS 14+ 和 Swift 6.0（Command Line Tools 自带）

首次运行需登录 [platform.deepseek.com](https://platform.deepseek.com)，之后自动保持 session。

## 🏗 项目结构

```
Sources/
├── App.swift              # MenuBarExtra 入口
├── APIService.swift        # 网页抓取 + API 拦截解析
├── DashboardView.swift     # 仪表盘 UI（堆叠条形图）
├── GlassBackground.swift   # 毛玻璃特效
├── Models.swift            # 数据模型 + DeepSeek 定价
├── PlatformAuth.swift      # 登录 + Keychain
├── VersionMark.swift       # 编译版本标记
└── ViewModel.swift         # 状态管理
```

## 🔐 原理

不依赖 API Key。通过 WKUserScript 注入拦截 `window.fetch`，在已登录的 WebView 中捕获平台自身的 API 响应，直接解析用量数据。

所有数据仅存储在本地 **Keychain** 和 **UserDefaults**，不上传任何第三方。

## 📄 License

MIT © IceCryStal

---

<p align="center"><sub>Made with ❤️ by IceCryStal</sub></p>
