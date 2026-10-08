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

<!-- ═════════════════════ DEMO PREVIEW PLACEHOLDER ═════════════════════ -->
> 🎬 **交互演示预览 / Interactive Showcase**
> 
> ```
> ┌────────────────────────────────────────────────────────────────────────┐
> │                                                                        │
> │                    [ Demo GIF / 交互动效视频预览 ]                       │
> │                                                                        │
> │        物理共面边缘滑出 · Metal 极光流体频谱 · 费茨法则人机工学边轨          │
> │                                                                        │
> └────────────────────────────────────────────────────────────────────────┘
> ```
<!-- ═════════════════════════════════════════════════════════════════════ -->

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
- **💻 边缘交互终端**：借鉴并基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 打造的常驻后台终端，具备完整的 VT100/Xterm 仿真、实时字体缩放与 Starship / Nerd Font 图标支持。
- **📐 人机工学分区布局**：根据光标天然移动轨迹，智能分为余光速览区、黄金操作区与快速轻扫区。
- **🌊 60 / 120 FPS 流体频谱**：基于 Metal GPU 渲染的实时音乐波形动效，在屏幕边缘自然流淌。
- **🖥 多显示器动态跟随**：自动跟随鼠标所在显示器，并在屏幕物理拼接缝隙处自动防误触。

---

### 🧩 内置插件模块

| 插件模块 | 图标 | 功能简介 |
| :--- | :---: | :--- |
| **交互终端** | `apple.terminal.fill` | 借鉴并基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 打造的常驻后台终端，支持 Starship / Nerd Font 与即时字体调节。 |
| **硬件脉搏** | `waveform.path.ecg` | 实时 CPU、内存、显卡、硬盘、温度与网络吞吐监控。 |
| **日程时间轴** | `calendar` | 当日日程纵览，自动提取会议链接（Zoom、腾讯会议、Google Meet 等）。 |
| **待办清单** | `checklist` | 系统提醒事项深度整合，支持就地勾选完成。 |
| **音乐律动** | `waveform` | Apple Music 播放控制与实时流体音频波形。 |
| **临时收纳架** | `tray.fill` | 访达文件随手拖拽暂存，保持桌面清爽。 |
| **即时便签** | `note.text` | 极速呼出的临时灵感备忘录与代码草稿纸。 |
| **终端跑道** | `terminal.fill` | 一键执行常用维护脚本与开发者常用自动化指令。 |

> 🚀 **未来可期**：更多实用插件、自定义小组件及扩展生态正在持续开发扩充中。

---

### ⌨️ 快捷键与防误触细节

Purah 的理念是“非请勿扰”，在无意触发时完全隐形，在使用时绝不丢失。

#### 唯一的快捷键
- **`⌥⇥` (Option + Tab)**：全局一键 **冻结 / 解冻** 导轨，伴随触感胶囊 HUD。全屏演示或沉浸写代码时随时隐匿所有边缘交互。

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
