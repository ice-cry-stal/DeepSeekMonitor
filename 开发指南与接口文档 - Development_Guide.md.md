# DeepSeek Monitor — 跨平台重写技术文档

> 本文档供 AI 读取并实现任意平台（Windows/Linux/Web）版本。

---

## 1. 功能概述

macOS 菜单栏常驻的 DeepSeek 平台 API 用量监控工具。

- 显示余额、今日花费、本月花费
- Token 消耗堆叠条形图（按模型拆分 + 今日/本月对比）
- 缓存命中率统计
- 每 6 分钟自动刷新
- 菜单栏自定义显示内容

---

## 2. 鉴权方案（核心难点）

DeepSeek 平台没有公开 API Key，只能用 **session cookie** 鉴权。

### 流程：

```
1. 用户通过内嵌浏览器手动登录 https://platform.deepseek.com
2. 登录成功后，拦截浏览器所有 API 请求的响应数据
3. 提取 cookie 持久化存储，后续请求复用
```

### 拦截方式（macOS 实现参考）：

在 WebView 加载前注入 JS 脚本，劫持 `window.fetch` 和 `XMLHttpRequest`：

```js
const origFetch = window.fetch;
window.fetch = function(...args) {
    const url = typeof args[0] === 'string' ? args[0] : args[0].url;
    return origFetch.apply(this, args).then(r => {
        if (url.indexOf('/api/') !== -1) {
            r.clone().text().then(body => {
                // 发送到原生层：{url, body}
                window.webkit.messageHandlers.capture.postMessage({url, body});
            });
        }
        return r;
    });
};
```

**Windows 替代方案**：用 WebView2 或 CEF，注入相同逻辑的 JS，通过 `window.chrome.webview.postMessage()` 回传数据。

**纯 HTTP 方案（无需浏览器）**：如果能从浏览器导出 cookie 字符串（F12 → Application → Cookies），可以直接用 requests/curl 带 cookie 请求 API，不需要 WebView。

---

## 3. 用到的 API 端点

Base URL: `https://platform.deepseek.com`

### 3.1 用户摘要（余额）

```
GET /api/v0/users/get_user_summary
```

响应格式：
```json
{
  "code": 0,
  "data": {
    "biz_code": 0,
    "biz_data": {
      "normal_wallets": [{"currency": "CNY", "balance": "10.4094126800000000"}],
      "monthly_costs": [{"currency": "CNY", "amount": "10.0010507200000000"}],
      "monthly_token_usage": "45652933"
    }
  }
}
```

### 3.2 用量金额（Token 数）

```
GET /api/v0/usage/amount?month=5&year=2026
```

响应格式：
```json
{
  "code": 0,
  "data": {
    "biz_code": 0,
    "biz_data": {
      "total": [
        {
          "model": "deepseek-v4-pro",
          "usage": [
            {"type": "PROMPT_TOKEN", "amount": "0"},
            {"type": "PROMPT_CACHE_HIT_TOKEN", "amount": "21451392"},
            {"type": "PROMPT_CACHE_MISS_TOKEN", "amount": "1277469"},
            {"type": "RESPONSE_TOKEN", "amount": "620701"},
            {"type": "REQUEST", "amount": "732"}
          ]
        },
        {
          "model": "deepseek-v4-flash",
          "usage": [ ... ]
        },
        {
          "model": "deepseek-chat & deepseek-reasoner",
          "usage": [ 全为 0，需过滤 ]
        }
      ],
      "days": [
        {
          "date": "2026-05-01",
          "data": [ /* 同上 model 结构 */ ]
        }
      ]
    }
  }
}
```

### 3.3 用量费用

```
GET /api/v0/usage/cost?month=5&year=2026
```

结构同上，但 amount 值为 CNY 金额（字符串），如 `"0.5362848000000000"`。

---

## 4. Token 类型映射

| API 字段 | 含义 |
|---------|------|
| `PROMPT_CACHE_HIT_TOKEN` | 缓存命中 Token |
| `PROMPT_CACHE_MISS_TOKEN` | 缓存未命中 Token |
| `RESPONSE_TOKEN` | 输出 Token |
| `REQUEST` | 请求次数 |
| `PROMPT_TOKEN` | 始终为 0，忽略 |

---

## 5. 定价模型

| 模型 | 缓存命中(每百万) | 缓存未命中(每百万) | 输出(每百万) |
|------|:---------:|:----------:|:------:|
| deepseek-v4-flash | ¥0.02 | ¥1.00 | ¥2.00 |
| deepseek-v4-pro   | ¥0.025 | ¥3.00 | ¥6.00 |

费用 = hit/1M × 命中单价 + miss/1M × 未命中单价 + output/1M × 输出单价

---

## 6. UI 布局

```
剩余 ¥10.41      今日 ¥5.36      本月 ¥10.00      ← 三列数字
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
■ 缓存未命中  ■ 缓存命中  ■ 输出                  ← 图例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
今日费用构成                          合计 ¥5.36
  ● V4Flash  [████¥0.94██¥0.42█¥0.53]     ¥1.89
  ● V4Pro    [██████¥3.83█¥0.54██¥3.72]   ¥3.47

今日 Token 消耗                       合计 40.1M
  ● V4Flash  [███0.9M█21.1M█0.3M]  22.3M  缓存命中率 95.8%
  ● V4Pro    [█0.9M██22.3M█0.4M]    23.3M  缓存命中率 95.9%

本月费用构成                          合计 ¥10.00
  ● V4Flash  [████¥0.94██¥0.42█¥0.53]     ¥1.91
  ● V4Pro    [██████¥3.83█¥0.54██¥3.72]   ¥8.09

本月 Token 消耗                       合计 45.7M
  ● V4Flash  [██0.9M█21.1M█0.3M]  22.3M  缓存命中率 95.8%
  ● V4Pro    [█1.3M█21.5M█0.6M]    23.3M  缓存命中率 94.5%
```

### 堆叠条形图规则：

- 三个分段：缓存未命中（浅绿）→ 缓存命中（绿）→ 输出（蓝）
- 分段之间**无间隙**，紧密连接成一条
- V4Flash 标签在条上方，V4Pro 标签在条下方
- Token 数值统一用 M 为单位，保留一位小数（如 21.1M）
- 费用数值显示 ¥x.xx 格式
- 条形右侧显示合计金额/Token 数
- Token 条额外显示缓存命中率百分比
- 今日无数据时隐藏「今日」两组

---

## 7. 数据刷新

每 6 分钟自动刷新。刷新时导航 WebView 到 `https://platform.deepseek.com/usage`，页面加载后 React 自动请求上述 API，拦截脚本捕获响应。提取后先设 `authState = .loggedOut` 让用户看到登录页，后台异步清除本地 cookie。

---

## 8. 技术栈建议

| 平台 | 推荐方案 |
|------|---------|
| Windows 原生 | C# WPF + WebView2 |
| 跨平台桌面 | Electron + React |
| 命令行/Python | requests + rich/termgraph |
| Web | 纯前端，用户手动粘贴 cookie |

---

## 9. 注意事项

- **必须过滤** `"deepseek-chat & deepseek-reasoner"` 模型（全为零）
- 所有 API amount 字段为**字符串**，需转换为数字
- month/year 参数可切换历史月份
- 退出登录需导航到 `https://platform.deepseek.com/profile` 并点击退出按钮
- 官方数据延迟约 5 分钟
