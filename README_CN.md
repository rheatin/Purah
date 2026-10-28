<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/Purah-icon-macOS-1024.png">
  <img src="assets/Purah-icon-macOS-1024.png" width="128" height="128" alt="Purah App Icon" />
</picture>

# Purah (普尔亚)
### macOS 物理边缘磁吸导轨 · 环境人机工学内核

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://apple.com/macos)
[![Platform Metal GPU](https://img.shields.io/badge/Metal-60%20%2F%20120%20FPS-147EFB?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/metal/)
[![Zero Block Click-Through](https://img.shields.io/badge/Windowing-Zero--Block%20Click--Through-success?style=flat-square)](https://github.com)
[![License MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

<br />

[**English**](README.md) &nbsp;|&nbsp; 简体中文

<br />

<!-- ═════════════════════ DEMO SHOWCASE ═════════════════════ -->
<p align="center">
  <img src="assets/purah-showcase-30s.gif" width="880" alt="Purah macOS 交互演示" style="border-radius: 10px; box-shadow: 0 16px 40px rgba(0,0,0,0.35);" />
  <br />
  <sub>🎬 <em>使用 video-shotcraft 运镜剪辑的 100% 真机屏幕实录 &middot; <a href="assets/purah-showcase-30s.mp4">查看 1080p 原声视频</a></em></sub>
</p>
<!-- ═══════════════════════════════════════════════════════════ -->

</div>

---

<br />

### 💡 什么是 Purah (普尔亚)？

**Purah (普尔亚)** 是一款超轻量的 macOS 桌面环境交互内核。平时它以细微的环境色条静谧贴附在屏幕物理最边缘，当鼠标滑向屏幕边框时，对应模块以自然的物理共面动效从屏幕边缘向中央平滑弹开。

Purah 纯粹驻留后台运行，不占据 Dock 栏，不抢夺输入焦点，并保证抽屉之外的透明区域对下层窗口与代码编辑器 **100% 穿透点击**。

---

### ✨ 核心特性

- **⚡️ 零阻挡点击穿透**：未唤出卡片的透明空间完全传递点击事件，绝不遮挡底层应用、访达或 IDE 的正常操作。
- **🎛 纯物理边框滑出动效**：卡片从屏幕边缘向中央平滑滑出，收回时利落归入黑边，无残影虚化。
- **🧱 统一三层弹性导轨引擎**：支持将任意模块像文件夹一样折叠成堆叠 (Stack)，拥挤页面可选开启动态呼吸弹性压缩 (Dynamic Breathing)，并通过多页空间 (Pagination) 与边缘传送门从容容纳海量组件。
- **📐 1:1 桌面实时导轨塑形器 (`⌃⌥E`)**：直接在桌面真实边框上实时塑形、自由拉伸、堆叠/解包、跨屏幕边缘和跨分页拖拽重排所有模块。
- **💾 完整配置备份与还原**：支持将完整工作区布局、全局快捷键与各插件偏好设置一键导出/导入为便携 JSON 文件，并支持一键恢复出厂设置。
- **💻 边缘交互终端**：基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 打造的多标签页常驻后台终端，具备完整 VT100/Xterm 仿真、一键 `cd` 追踪访达最前端目录、实时字体缩放与 Starship / Nerd Font 支持。
- **🌊 60 / 120 FPS 流体频谱**：基于 Metal GPU 渲染的实时音乐波形动效，在屏幕边缘自然流淌。
- **🖥 多显示器动态跟随**：自动跟随鼠标所在显示器，并在屏幕物理拼接缝隙处自动防误触。

---

### 🧩 内置插件模块 (10 大内置插件)

| 插件模块 | 图标 | 功能简介 |
| :--- | :---: | :--- |
| **AI 助理** | `sparkles` | 多模型 AI 工作台，原生支持端侧 Apple Intelligence (`FoundationModels`)、本地 CLI Agent (`claude`、`codex`、`ollama` 及自定义工具) 与 OpenAI / Anthropic / Ollama HTTP API。支持最前端文本/选区即时捕获、50/50 分割拖拽区（新会话 vs 追加上下文）、内联 Diff 润色、自定义角色提示词、内置本地文件 Skill 及 MCP 服务器联动。 |
| **硬件脉搏** | `waveform.path.ecg` | 深度 Darwin / IOKit 硬件遥测，提供统一 2x2 概览网格（CPU 用户态/系统态/负载/温度、显卡、内存应用/联动/压缩/交换、电池健康度与循环）、全宽网络 I/O 卡片、磁盘读写吞吐及完整进程检查器 (Process Inspector)。 |
| **临时收纳架** | `tray.fill` | 访达文件随手拖拽暂存，支持框选多选 (Rubber-band)、批量拖拽出轨、一键 ZIP 打包与隔空投送 (AirDrop)，以及固定交互式悬浮边车预览 (`👁`)。 |
| **智能剪贴板** | `doc.on.clipboard.fill` | 零内存常驻历史管理器，支持框选多选、批量拖拽、一键 ZIP 打包与 AirDrop、固定交互式悬浮边车预览 (`👁`)、颜色预览、图片快照与模糊快筛。 |
| **即时便签** | `note.text` | Typora 式即时渲染 Markdown 编辑器，支持可调列宽表格、跨文件夹即时快搜、图片就地粘贴与一键导出 `.md`。 |
| **交互终端** | `apple.terminal.fill` | 基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 打造的多标签页常驻后台终端，支持一键 `cd` 至当前访达目录、Starship / Nerd Font 与即时字体调节，并内置自然语言命令 (`??`)，用一句话写出你想要的命令。 |
| **音乐律动** | `waveform` | Apple Music 播放控制与实时流体音频波形，支持平滑进度拖拽。 |
| **日程时间轴** | `calendar` | 当日日程纵览，自动提取会议链接（Zoom、腾讯会议、Google Meet 等）。 |
| **待办清单** | `checklist` | 系统提醒事项深度整合，支持就地勾选完成。 |
| **终端跑道** | `terminal.fill` | 一键执行常用维护脚本与开发者常用自动化指令。 |

> 🚀 **未来可期**：更多实用插件、自定义小组件及扩展生态正在持续开发扩充中。

---

### ⚡ 终端自然语言命令 (`??` / `???`)

没人记得住所有参数。在你已经打开的终端里用一句话描述任务，Purah 帮你把命令写出来：

```zsh
❯ ?? 找出所有大于 1G 的文件，按大小排序
⚡ Purah 正在思考…
find . -type f -size +1g -exec du -h {} + | sort -rh
```

- **不会自动执行。** 建议只会填进输入行，绝不替你回车 —— 先看清、可修改，再按 Return。
- **`???` 解释上一条命令**，结合它的退出状态和刚刚发生的失败。
- **风险等级由本地判定，绝不采信模型。** 每条建议都会由 `CommandRiskClassifier` 按固定词表判为 `safe` / `caution` / `dangerous`，破坏性命令在你回车之前就以红色警告标出。
- **它会核对本机，而不只是模型。** 如果答案里点名的程序本机并不存在（比如 Apple 在 macOS 14.4 删掉的 `airport`），Purah 会把这一事实送回模型让它重答一次，而不是给你一条注定跑不通的命令。
- **输入 `??` 时两个问号会变成粉色斜体**，回车之前就能看出已进入 AI 模式；提示文字只放在抽屉底部，点击 `⚡ ??` 即可自动键入这两个字符。
- **与 AI 助理同源。** 供应商、CLI、接口地址与密钥全部复用 AI 助理的设置，不需要第二处配置。
- **仅支持 zsh，且不改动你的 dotfiles。** 终端以托管 `ZDOTDIR` 启动，先 source 你真实的 `.zshenv` / `.zshrc`，再追加别名。关闭该功能只是不再设置这个变量。
- **开关位置**：交互终端插件 → **设置 → 自然语言命令**。

---

### ⌨️ 全局快捷键与人机工学交互

Purah 的理念是“非请勿扰”，在无意触发时完全隐形，在使用时绝不丢失。

#### 全局快捷键
- **`⌥⇥` (Option + Tab)**：全局一键 **冻结 / 解冻** 导轨，伴随触感胶囊 HUD（可在设置中自定义快捷键）。全屏演示或沉浸写代码时随时隐匿所有边缘交互。
- **`⌃⌥E` (Control + Option + E)**：全局一键呼出 **1:1 桌面实时导轨塑形器**（可在设置中自定义快捷键）。直接在屏幕边框上实时塑形、拉伸尺寸、堆叠与拖拽调整模块。

#### 防误触与防丢失细节
- **边缘轻触唤出**：光标滑到屏幕 14px 物理边框区域，抽屉即刻平滑滑出。
- **快速划过防误触**：快速横扫屏幕或跨屏移动时自动压制触发，避免意外误弹。
- **推边即刻破界**：有意贴紧外侧边缘持续推边，可瞬间打破门禁 0ms 唤出。
- **150ms 离开缓冲 (防误关)**：光标离开卡片前往边缘按钮时提供 150ms 缓冲，防止误移出导致卡片突然收起。
- **捕获走廊 (防丢失)**：卡片外围设有隐形捕获缓冲带，大幅甩动光标也不会意外丢失交互状态。

---

### 🛠 编译与测试

```bash
# 克隆仓库
git clone https://github.com/rheatin/Purah.git
cd Purah

# 运行单元测试
swift test --disable-sandbox

# 生产环境 Release 构建
swift build -c release --disable-sandbox

# 运行二进制
.build/release/PurahApp
```

---

### 🙏 致谢与参考

- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** (作者 Miguel de Icaza) — 为 Purah 的边缘 GPU 加速终端模拟提供核心支持。
- **[MacToastKit](https://github.com/daniyalmaster693/MacToastKit)** (作者 daniyalmaster693) — 为 Purah 的极简轻量 macOS HUD Toast 提示体系提供设计灵感与参考。

---

### 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源协议。

<div align="center">
<sub>Crafted with ergonomic obsession for macOS power users. Inspired by the Purah Pad concept.</sub>
</div>
