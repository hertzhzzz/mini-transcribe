import sys
import os
import time
import threading
import queue
import json
import re
import urllib.request
import urllib.parse
import numpy as np
import sounddevice as sd
import sherpa_onnx
from http.server import HTTPServer, BaseHTTPRequestHandler

SAMPLE_RATE = 16000
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "models", "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17")

# 全局共享广播队列（用于推送到手机）
mobile_subscribers = []
subscribers_lock = threading.Lock()

def log_event(data):
    try:
        json_str = json.dumps(data, ensure_ascii=False)
        sys.stdout.write(json_str + "\n")
        sys.stdout.flush()
        
        # 广播给连在 Mac 上的 iPhone 手机端
        with subscribers_lock:
            for q in mobile_subscribers:
                q.put(json_str)
    except Exception:
        pass

def translate_if_needed(text):
    """
    智能语言路由：
    - 纯中文 -> 不需要翻译，返回 None
    - 英文或 Singlish 占主导 -> 翻译成优雅中文
    """
    english_words = re.findall(r'[a-zA-Z]{2,}', text)
    chinese_chars = re.findall(r'[\u4e00-\u9fff]', text)
    
    # 判定：含两个以上英文单词，或者包含英文且中文少于 3 个字
    needs_tr = len(english_words) >= 2 or (len(english_words) >= 1 and len(chinese_chars) < 3)
    if not needs_tr:
        return None
        
    try:
        url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=" + urllib.parse.quote(text)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=2.5) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            translated = "".join([part[0] for part in data[0] if part[0]])
            # 如果翻译出来的和原文一样（比如全是专有名词），就不显示多余译文
            if translated.strip().lower() == text.strip().lower():
                return None
            return translated.strip()
    except Exception:
        return None

class DirectSenseVoiceEngine:
    def __init__(self):
        log_event({"type": "status", "message": "正在加载 SenseVoice 混杂多语言模型..."})
        
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
            self.audio_queue.put(indata.flatten().copy())

    def start(self):
        if self.is_recording:
            return
        try:
            self.is_recording = True
            self.audio_queue = queue.Queue()
            
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
            log_event({"type": "started", "message": "🎙️ 正在实时监听麦克风（中英混杂+自动翻译）..."})
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
        cleaned = re.sub(r"<\|.*?\|>", "", text)
        cleaned = re.sub(r"[。，？！,.?!]$", "", cleaned.strip())
        return cleaned.strip()

    def _process_loop(self):
        buffer = []
        silence_chunks = 0
        has_spoken = False
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
                
                if np.max(np.abs(audio_samples)) < SPEECH_ENERGY_THRESHOLD:
                    continue
                
                try:
                    stream = self.recognizer.create_stream()
                    stream.accept_waveform(SAMPLE_RATE, audio_samples)
                    self.recognizer.decode_stream(stream)
                    raw_text = stream.result.text
                    text = self.clean_text(raw_text)
                    
                    if text and len(text) > 1:
                        # 触发自动智能翻译（英语/Singlish 自动翻成中文，中文保持原样）
                        translation = translate_if_needed(text)
                        log_event({
                            "type": "transcription",
                            "text": text,
                            "translation": translation
                        })
                except Exception as e:
                    log_event({"type": "error", "message": f"解码异常: {str(e)}"})

# ================= 手机端轻量 Web/画中画悬浮窗服务器 =================
MOBILE_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>MiniTranscribe 手机悬浮字幕</title>
  <style>
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    body {
      margin: 0; padding: 16px;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: #0f1117; color: #f0f3f6;
      display: flex; flex-direction: column; height: 100vh;
    }
    .header {
      display: flex; justify-content: space-between; align-items: center;
      padding-bottom: 12px; border-bottom: 1px solid rgba(255,255,255,0.1);
    }
    .title { font-weight: 600; font-size: 16px; display: flex; align-items: center; gap: 6px; }
    .status-dot { width: 8px; height: 8px; border-radius: 50%; background: #10b981; }
    .pip-btn {
      background: #2563eb; color: #fff; border: none;
      padding: 8px 14px; border-radius: 20px; font-size: 13px; font-weight: 600;
      display: flex; align-items: center; gap: 4px; cursor: pointer;
    }
    .pip-btn:active { opacity: 0.8; }
    #video-container { display: none; }
    .transcript-box {
      flex: 1; overflow-y: auto; padding: 12px 0;
      display: flex; flex-direction: column; gap: 12px;
    }
    .card {
      background: rgba(255,255,255,0.06);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 12px; padding: 12px 14px;
      animation: fadeIn 0.25s ease-out;
    }
    .original { font-size: 15px; line-height: 1.4; color: #f3f4f6; }
    .translation {
      margin-top: 6px; font-size: 13px; line-height: 1.4;
      color: #60a5fa; font-weight: 500;
      border-top: 1px dashed rgba(255,255,255,0.1);
      padding-top: 5px;
    }
    .tip {
      font-size: 12px; color: #9ca3af; text-align: center;
      margin-top: auto; padding: 8px 0;
    }
    @keyframes fadeIn { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
  </style>
</head>
<body>
  <div class="header">
    <div class="title"><span class="status-dot"></span> 实时中英转录</div>
    <button class="pip-btn" id="startPip">📱 开启手机悬浮窗</button>
  </div>
  
  <div class="transcript-box" id="box">
    <div class="card">
      <div class="original">已连接电脑端。打电话时保持此页面，或点击右上角开启「手机画中画悬浮窗」。</div>
    </div>
  </div>

  <div class="tip">💡 英文/Singlish 会自动在下方翻译为中文</div>

  <canvas id="pipCanvas" width="480" height="240" style="display:none;"></canvas>
  <video id="pipVideo" autoplay playsinline muted style="display:none;"></video>

  <script>
    const box = document.getElementById('box');
    const startPipBtn = document.getElementById('startPip');
    const canvas = document.getElementById('pipCanvas');
    const video = document.getElementById('pipVideo');
    const ctx = canvas.getContext('2d');

    let latestText = "MiniTranscribe 准备就绪";
    let latestTr = "";

    function renderCanvas() {
      // 绘制画中画毛玻璃深色背景卡片
      ctx.fillStyle = "#111827";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      
      ctx.fillStyle = "#3b82f6";
      ctx.fillRect(0, 0, 6, canvas.height); // 左边装饰条

      // 原文
      ctx.fillStyle = "#f9fafb";
      ctx.font = "bold 20px -apple-system, sans-serif";
      wrapText(ctx, latestText, 20, 42, 440, 26);

      // 译文
      if (latestTr) {
        ctx.fillStyle = "#60a5fa";
        ctx.font = "17px -apple-system, sans-serif";
        wrapText(ctx, "译: " + latestTr, 20, 150, 440, 24);
      }
    }

    function wrapText(ctx, text, x, y, maxWidth, lineHeight) {
      const words = text.split('');
      let line = '';
      for (let n = 0; n < words.length; n++) {
        let testLine = line + words[n];
        let metrics = ctx.measureText(testLine);
        if (metrics.width > maxWidth && n > 0) {
          ctx.fillText(line, x, y);
          line = words[n];
          y += lineHeight;
          if (y > 220) break;
        } else {
          line = testLine;
        }
      }
      ctx.fillText(line, x, y);
    }

    setInterval(renderCanvas, 200);

    // 开启系统画中画
    startPipBtn.addEventListener('click', async () => {
      try {
        if (!video.srcObject) {
          const stream = canvas.captureStream(10);
          video.srcObject = stream;
          await video.play();
        }
        if (document.pictureInPictureElement) {
          await document.exitPictureInPicture();
        } else {
          await video.requestPictureInPicture();
        }
      } catch (err) {
        alert("开启画中画提示: " + err.message + "\\n请在 Safari 浏览器中点击，并允许画中画权限。");
      }
    });

    // 建立 SSE 实时推送
    const evtSource = new EventSource('/events');
    evtSource.onmessage = function(e) {
      try {
        const data = JSON.parse(e.data);
        if (data.type === 'transcription') {
          latestText = data.text;
          latestTr = data.translation || "";
          
          const card = document.createElement('div');
          card.className = 'card';
          
          let html = `<div class="original">${escapeHtml(data.text)}</div>`;
          if (data.translation) {
            html += `<div class="translation">🇨🇳 ${escapeHtml(data.translation)}</div>`;
          }
          card.innerHTML = html;
          box.appendChild(card);
          box.scrollTop = box.scrollHeight;
        }
      } catch(err){}
    };

    function escapeHtml(str) {
      return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
  </script>
</body>
</html>
"""

class SimpleServer(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(MOBILE_HTML.encode('utf-8'))
        elif self.path == "/events":
            # Server-Sent Events 流式推送到手机
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            
            client_q = queue.Queue()
            with subscribers_lock:
                mobile_subscribers.append(client_q)
            try:
                while True:
                    msg = client_q.get()
                    self.wfile.write(f"data: {msg}\n\n".encode('utf-8'))
                    self.wfile.flush()
            except Exception:
                pass
            finally:
                with subscribers_lock:
                    if client_q in mobile_subscribers:
                        mobile_subscribers.remove(client_q)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # 静默 HTTP 访问日志
        pass

def run_http_server():
    server = HTTPServer(('0.0.0.0', 8998), SimpleServer)
    server.serve_forever()

def start_cloudflare_tunnel():
    cf_path = "/opt/homebrew/bin/cloudflared"
    if not os.path.exists(cf_path):
        return
    import subprocess
    try:
        proc = subprocess.Popen(
            [cf_path, "tunnel", "--url", "http://127.0.0.1:8998"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        for line in proc.stderr:
            match = re.search(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", line)
            if match:
                tunnel_url = match.group(0)
                log_event({"type": "tunnel_ready", "url": tunnel_url})
                break
    except Exception:
        pass

def main():
    # 启动后台手机服务端口 8998
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()
    
    # 启动后台公网穿透
    cf_thread = threading.Thread(target=start_cloudflare_tunnel, daemon=True)
    cf_thread.start()
    
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
