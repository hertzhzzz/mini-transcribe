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
    """自动启动免费 Cloudflare 安全隧道，让手机在任何 4G/5G/外网下都能直接访问"""
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
    
    # 启动 Cloudflare 免费远程公网穿透
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
