import SwiftUI
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    @StateObject private var engine = WhisperProcessManager()
    @State private var copiedNotice = false
    @State private var isAlwaysOnTop = true
    
    var body: some View {
        VStack(spacing: 10) {
            // 顶栏控制区（左侧留出 68px 给原生红黄绿三色按钮）
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 68)
                
                // 录制按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        engine.toggleRecording()
                    }
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(engine.isRecording ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                            .shadow(color: engine.isRecording ? Color.red.opacity(0.8) : Color.clear, radius: 3)
                        Text(engine.isRecording ? "停止录制" : "点击录制")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(engine.isRecording ? Color.red.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(engine.isRecording ? Color.red.opacity(0.5) : Color.gray.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!engine.isEngineReady)
                
                // 置顶开关（勾选按钮）
                Button(action: {
                    isAlwaysOnTop.toggle()
                    updateWindowPin(isAlwaysOnTop)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin.slash")
                            .font(.system(size: 10))
                            .foregroundColor(isAlwaysOnTop ? .orange : .secondary)
                        Text("置顶")
                            .font(.system(size: 11, weight: isAlwaysOnTop ? .semibold : .regular))
                            .foregroundColor(isAlwaysOnTop ? .primary : .secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(isAlwaysOnTop ? Color.orange.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isAlwaysOnTop ? Color.orange.opacity(0.35) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(isAlwaysOnTop ? "当前：始终置顶（点击取消）" : "当前：普通窗口（点击置顶）")
                
                // 手机画中画同步入口提示
                Link(destination: URL(string: "http://192.168.1.23:8998")!) {
                    HStack(spacing: 3) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 10))
                        Text("手机悬浮")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("手机浏览器打开此链接，可将字幕作为画中画悬浮在手机任意界面上")
                
                Spacer()
                
                // 复制按钮
                Button(action: copyToClipboard) {
                    Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(copiedNotice ? .green : .secondary)
                        .padding(5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("复制全部转录与译文")
                
                // 清空按钮
                Button(action: {
                    engine.clearAll()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("清空内容")
            }
            .padding(.top, 10)
            
            // 转录文本展示区
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                    )
                
                if engine.items.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("点击「点击录制」开始通话监听\n中英文或 Singlish 自动混合识别\n💡 英语/Singlish 会自动在下方给出中文译文")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(engine.items) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.text)
                                            .font(.system(size: 13, weight: .regular))
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                        
                                        if let tr = item.translation {
                                            HStack(alignment: .top, spacing: 4) {
                                                Text("🇨🇳 译:")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.blue)
                                                Text(tr)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.blue.opacity(0.9))
                                                    .textSelection(.enabled)
                                            }
                                            .padding(.top, 1)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                    .cornerRadius(6)
                                    .id(item.id)
                                }
                            }
                            .padding(10)
                        }
                        .onChange(of: engine.items.count) { _ in
                            if let lastId = engine.items.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // 底部状态栏
            HStack {
                Text(engine.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("📱 手机同步: 192.168.1.23:8998")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                if copiedNotice {
                    Text("已复制!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(minWidth: 460, minHeight: 300)
        .background(VisualEffectBlur(material: .headerView, blendingMode: .behindWindow))
    }
    
    private func updateWindowPin(_ pin: Bool) {
        if let window = NSApplication.shared.windows.first {
            window.level = pin ? .floating : .normal
        }
    }
    
    private func copyToClipboard() {
        let lines = engine.items.map { item -> String in
            if let tr = item.translation {
                return "\(item.text)\n(译: \(tr))"
            }
            return item.text
        }
        let textToCopy = lines.joined(separator: "\n\n")
        guard !textToCopy.isEmpty else { return }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        
        withAnimation {
            copiedNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                copiedNotice = false
            }
        }
    }
}
