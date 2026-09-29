# MiniTranscribe 🎙️

> 专为**中英混合、Singlish（新加坡英语）** 通话场景打造的 **macOS 极简实时悬浮窗转录工具**。
> 基于 **SwiftUI 原生悬浮窗** + **SenseVoice 跨语言多词元识别内核**，100% 本地离线运行，零费用、低延迟、完全保护隐私。

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue" />
  <img src="https://img.shields.io/badge/Engine-SenseVoice%20ONNX-orange" />
  <img src="https://img.shields.io/badge/License-MIT-green" />
</p>

---

## ✨ 特性亮点

- **🇸🇬 专治中英混杂与口音（Code-Switching & Singlish）**：
  - 传统 ASR 遇到中英夹杂（例如：“*这个 project 明天一定要 confirm 掉 lah*”）容易丢词或乱码。
  - 采用 **SenseVoiceSmall INT8** 跨语言联合解码，无需手动切换语言，中英文自由穿插无缝识别。
- **🪟 极致精简原生悬浮窗**：
  - 始终置顶（Floating Panel），开会、打微信电话、看文档时绝不被遮挡。
  - 点击窗口空白处即可随意拖动，原生 macOS 毛玻璃质感。
- **⚡️ 实时能量断句（Real-time Energy Window）**：
  - 毫秒级监测人声起止，说话停顿立即自动出字，绝不吞字、绝不卡顿。
- **🔒 100% 本地离线**：
  - 音频不出本地，无任何 API Key 依赖，零花费，无风扇发热困扰。
- **📋 一键快捷操作**：
  - 右上角内置一键复制全文、一键清空记录。

---

## 🛠️ 快速安装与运行

### 运行环境
- macOS 13.0+ (Apple Silicon M1/M2/M3/M4 推荐)
- Python 3.10+
- 系统自带 Swift 编译器（Xcode / Command Line Tools）

### 一键构建与启动

克隆本项目到本地，执行一键配置脚本：

```bash
git clone https://github.com/hertzhzzz/mini-transcribe.git
cd mini-transcribe
./setup.sh
```

脚本会自动：
1. 安装 `sounddevice`、`sherpa-onnx` 等极轻量依赖。
2. 自动下载预构建的 SenseVoiceSmall ONNX 模型。
3. 编译出原生的 `MiniTranscribe.app`。

完成之后，直接在访达中双击 `MiniTranscribe.app` 或在终端运行：
```bash
open MiniTranscribe.app
```

---

## 📖 使用技巧

1. **初次启动**：请在 macOS 弹出的系统提示中允许**麦克风访问权限**。
2. **开始通话**：
   - 点击 **【点击录制】**（小红点点亮），即可开始正常通话。
   - 对着麦克风自然说中英文混杂语句，每说完一句并稍作停顿，文字便会实时向下追加。
3. **通话结束**：
   - 点击右上角 **📋 复制图标**，即可将全部对话文字一键粘贴至备忘录、文档或聊天软件中。

---

## 📄 License

MIT License © 2026 hertzhzzz
