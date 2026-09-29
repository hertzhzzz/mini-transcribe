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
    
    var body: some View {
        VStack(spacing: 10) {
            // 顶栏控制区（左侧留出 68px 给原生红黄绿三色按钮，完美避开重叠）
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
                
                // 智能混杂标识
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("SenseVoice 中英/Singlish 混杂")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(5)
                
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
                .help("复制全部转录文字")
                
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
                
                if engine.transcript.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("点击「点击录制」开始通话监听\n中英文或 Singlish 自动混合识别")
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
                            Text(engine.transcript)
                                .font(.system(size: 13, weight: .regular))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .id("bottomTarget")
                        }
                        .onChange(of: engine.transcript) { _ in
                            proxy.scrollTo("bottomTarget", anchor: .bottom)
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
        .frame(minWidth: 420, minHeight: 280)
        .background(VisualEffectBlur(material: .headerView, blendingMode: .behindWindow))
    }
    
    private func copyToClipboard() {
        let textToCopy = engine.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
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
