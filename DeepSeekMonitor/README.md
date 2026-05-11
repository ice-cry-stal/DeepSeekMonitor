# DeepSeek Monitor

macOS 菜单栏 DeepSeek 平台用量实时监控工具。

## 功能

- 菜单栏常驻，显示余额 / 今日花费 / 本月花费
- 费用与 Token 消耗堆叠条形图，今日 vs 本月对比
- 按模型拆分（V4Flash / V4Pro），缓存命中率一目了然
- 每 6 分钟自动刷新，数据实时同步

## 系统要求

- macOS 14+
- Swift 6.0+（Command Line Tools）

## 安装 & 运行

```bash
cd DeepSeekMonitor
bash build.sh
```

首次运行需登录 [platform.deepseek.com](https://platform.deepseek.com)，登录后自动提取 session 完成鉴权。

## 项目结构

```
Sources/
├── App.swift              # 入口 & 设置页
├── APIService.swift        # 网页抓取 & API 解析
├── DashboardView.swift     # 仪表盘主界面
├── GlassBackground.swift   # 毛玻璃效果
├── Models.swift            # 数据模型 & 定价
├── PlatformAuth.swift      # 登录 & Keychain
├── VersionMark.swift       # 编译版本标记
└── ViewModel.swift         # 状态管理
```

## 隐私说明

- 所有数据仅存储在本地 Keychain 和 UserDefaults
- 不会上传任何数据到第三方服务器
- 不会在本地创建额外文件

## License

MIT
