import sys
import os
import time
import threading
import queue
import json
import re
import numpy as np
import sounddevice as sd
import sherpa_onnx

SAMPLE_RATE = 16000
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "models", "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17")

def log_event(data):
    try:
        sys.stdout.write(json.dumps(data, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except Exception:
        pass

class DirectSenseVoiceEngine:
    def __init__(self):
        log_event({"type": "status", "message": "正在加载 SenseVoice 核心混杂多语言模型..."})
        
        self.recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=os.path.join(MODEL_DIR, "model.int8.onnx"),
            tokens=os.path.join(MODEL_DIR, "tokens.txt"),
            use_itn=True,
            num_threads=4
        )
        
        self.audio_queue = queue.Queue()
        self.is_recording = False
        self.stream = None
        self.worker_thread = None
        log_event({"type": "status", "message": "模型就绪（SenseVoice 核心引擎）"})

    def audio_callback(self, indata, frames, time_info, status):
        if self.is_recording:
            # 存入一维 float32
            self.audio_queue.put(indata.flatten().copy())

    def start(self):
        if self.is_recording:
            return
        
        try:
            self.is_recording = True
            self.audio_queue = queue.Queue()
            
            # 块大小 0.25 秒
            block_size = int(SAMPLE_RATE * 0.25)
            self.stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=1,
                dtype='float32',
                blocksize=block_size,
                callback=self.audio_callback
            )
            self.stream.start()
            
            self.worker_thread = threading.Thread(target=self._process_loop, daemon=True)
            self.worker_thread.start()
            log_event({"type": "started", "message": "🎙️ 正在实时监听麦克风（中英混杂）..."})
        except Exception as e:
            self.is_recording = False
            log_event({"type": "error", "message": f"麦克风打开失败: {str(e)}"})

    def stop(self):
        if not self.is_recording:
            return
        self.is_recording = False
        if self.stream:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception:
                pass
            self.stream = None
        log_event({"type": "stopped", "message": "已停止录制"})

    def clean_text(self, text):
        # 去除特殊标签（如 <|zh|> <|HAPPY|> 等）
        cleaned = re.sub(r"<\|.*?\|>", "", text)
        cleaned = re.sub(r"[。，？！,.?!]$", "", cleaned.strip())
        return cleaned.strip()

    def _process_loop(self):
        buffer = []
        silence_chunks = 0
        has_spoken = False
        
        # 0.25 秒一个 chunk
        # 能量阈值判断是否在说话 (MacBook Air 麦克风说话时 RMS 通常在 0.005 以上)
        SPEECH_ENERGY_THRESHOLD = 0.005
        
        while self.is_recording or not self.audio_queue.empty():
            try:
                chunk = self.audio_queue.get(timeout=0.25)
            except queue.Empty:
                continue
                
            buffer.append(chunk)
            rms = np.sqrt(np.mean(chunk**2))
            
            if rms >= SPEECH_ENERGY_THRESHOLD:
                has_spoken = True
                silence_chunks = 0
            else:
                if has_spoken:
                    silence_chunks += 1
            
            # 断句触发条件：
            # 1. 之前检测到了人声，且停顿了约 0.75 秒 (3 个静音 chunk)，且总长 >= 1.5 秒
            # 2. 或者累积说话超过 7 秒强行断句
            total_duration = len(buffer) * 0.25
            should_transcribe = False
            
            if has_spoken and silence_chunks >= 3 and total_duration >= 1.2:
                should_transcribe = True
            elif total_duration >= 7.0:
                should_transcribe = True
                
            if should_transcribe:
                audio_samples = np.concatenate(buffer).astype(np.float32)
                buffer = []
                silence_chunks = 0
                has_spoken = False
                
                # 如果整段最大音量太微弱则跳过
                if np.max(np.abs(audio_samples)) < SPEECH_ENERGY_THRESHOLD:
                    continue
                
                # 送入 SenseVoice 模型解码
                try:
                    stream = self.recognizer.create_stream()
                    stream.accept_waveform(SAMPLE_RATE, audio_samples)
                    self.recognizer.decode_stream(stream)
                    raw_text = stream.result.text
                    text = self.clean_text(raw_text)
                    
                    if text and len(text) > 1:
                        log_event({"type": "transcription", "text": text})
                except Exception as e:
                    log_event({"type": "error", "message": f"解码异常: {str(e)}"})

def main():
    engine = DirectSenseVoiceEngine()
    for line in sys.stdin:
        cmd = line.strip().lower()
        if cmd == "start":
            engine.start()
        elif cmd == "stop":
            engine.stop()
        elif cmd == "exit":
            engine.stop()
            break

if __name__ == "__main__":
    main()
