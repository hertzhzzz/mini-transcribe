import Foundation
import Combine

struct TranscribeMessage: Codable {
    let type: String
    let message: String?
    let text: String?
    let translation: String?
}

struct TranscriptItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let translation: String?
}

class WhisperProcessManager: ObservableObject {
    @Published var isRecording = false
    @Published var items: [TranscriptItem] = []
    @Published var statusMessage = "正在初始化 SenseVoice 引擎..."
    @Published var isEngineReady = false
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    
    init() {
        startBackend()
    }
    
    deinit {
        stopBackend()
    }
    
    func startBackend() {
        let pythonPath = "/opt/homebrew/bin/python3"
        let scriptPath = "/Users/mark/Projects/mini-transcribe/whisper_backend.py"
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [scriptPath]
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.standardError
        
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")
                for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    self?.handleLine(line)
                }
            }
        }
        
        do {
            try proc.run()
            self.process = proc
            self.inputPipe = inPipe
            self.outputPipe = outPipe
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "启动后端失败: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            let msg = try JSONDecoder().decode(TranscribeMessage.self, from: data)
            DispatchQueue.main.async {
                switch msg.type {
                case "status":
                    if let m = msg.message {
                        self.statusMessage = m
                        if m.contains("准备就绪") || m.contains("就绪") {
                            self.isEngineReady = true
                        }
                    }
                case "started":
                    self.isRecording = true
                    if let m = msg.message { self.statusMessage = m }
                case "stopped":
                    self.isRecording = false
                    if let m = msg.message { self.statusMessage = m }
                case "transcription":
                    if let text = msg.text, !text.isEmpty {
                        self.items.append(TranscriptItem(text: text, translation: msg.translation))
                    }
                case "error":
                    if let m = msg.message {
                        self.statusMessage = "错误: \(m)"
                    }
                default:
                    break
                }
            }
        } catch {
            // Non-json
        }
    }
    
    func toggleRecording() {
        if isRecording {
            sendCommand("stop\n")
        } else {
            sendCommand("start\n")
        }
    }
    
    private func sendCommand(_ cmd: String) {
        guard let data = cmd.data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
    }
    
    func clearAll() {
        items.removeAll()
        statusMessage = "已清空内容"
    }
    
    func stopBackend() {
        sendCommand("exit\n")
        process?.terminate()
        process = nil
    }
}
