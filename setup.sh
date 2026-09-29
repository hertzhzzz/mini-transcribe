#!/usr/bin/env bash
set -e

echo "=== 正在准备 MiniTranscribe 环境与模型 ==="

# 1. 安装 Python 依赖
pip install sounddevice numpy sherpa-onnx --break-system-packages

# 2. 下载模型文件
MODELS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/models"
mkdir -p "$MODELS_DIR"

SENSE_DIR="$MODELS_DIR/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
if [ ! -d "$SENSE_DIR" ]; then
    echo "正在下载 SenseVoice 多语言模型 (约 150MB)..."
    curl -L "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2" -o "$MODELS_DIR/sensevoice.tar.bz2"
    tar -xjf "$MODELS_DIR/sensevoice.tar.bz2" -C "$MODELS_DIR"
    rm "$MODELS_DIR/sensevoice.tar.bz2"
    echo "模型下载解压完成！"
else
    echo "SenseVoice 模型已就绪。"
fi

echo "=== 正在构建 macOS 原生悬浮窗应用 ==="
swift build -c release

APP_DIR="MiniTranscribe.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp .build/release/MiniTranscribe "$APP_DIR/Contents/MacOS/MiniTranscribe"
cp Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "🎉 构建完成！直接运行: open MiniTranscribe.app"
