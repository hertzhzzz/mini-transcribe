import Foundation
import Speech
import AVFoundation
import Combine

enum TranscribeLanguage: String, CaseIterable, Identifiable {
    case enSG = "en-SG"
    case zhCN = "zh-CN"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .enSG: return "🇸🇬 新加坡英语 (Singlish/En)"
        case .zhCN: return "🇨🇳 中文 (Chinese)"
        }
    }
}

class SpeechManager: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var currentSegment = ""
    @Published var statusMessage = "准备就绪，点击开始录音"
    @Published var selectedLanguage: TranscribeLanguage = .enSG {
        didSet {
            setupRecognizer()
        }
    }
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    init() {
        setupRecognizer()
    }
    
    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLanguage.rawValue))
    }
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            completion(granted)
                        }
                    }
                default:
                    completion(false)
                }
            }
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        requestPermissions { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.statusMessage = "请在系统设置中允许麦克风和语音识别权限"
                return
            }
            self.beginAudioSession()
        }
    }
    
    private func beginAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        setupRecognizer()
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            statusMessage = "语音识别器当前不可用"
            return
        }
        
        let audioSessionNode = audioEngine.inputNode
        let recordingFormat = audioSessionNode.outputFormat(forBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            statusMessage = "无法创建识别请求"
            return
        }
        
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    let formattedString = result.bestTranscription.formattedString
                    self.currentSegment = formattedString
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                // 209/216 属于正常停止或超时重连
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 209 || nsError.code == 216) {
                    // Ignore benign stop errors
                } else if self.isRecording {
                    DispatchQueue.main.async {
                        self.statusMessage = "识别提醒: \(error.localizedDescription)"
                    }
                }
            }
        }
        
        audioSessionNode.removeTap(onBus: 0)
        audioSessionNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, when) in
            self?.recognitionRequest?.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            statusMessage = "🎙️ 正在实时监听麦克风..."
        } catch {
            statusMessage = "音频启动失败: \(error.localizedDescription)"
            isRecording = false
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        
        isRecording = false
        statusMessage = "已停止录制"
        
        // 合并本次结果到历史
        if !currentSegment.isEmpty {
            if transcript.isEmpty {
                transcript = currentSegment
            } else {
                transcript += "\n\n" + currentSegment
            }
            currentSegment = ""
        }
    }
    
    func clearAll() {
        transcript = ""
        currentSegment = ""
        statusMessage = "已清空"
    }
    
    var fullDisplayText: String {
        var parts: [String] = []
        if !transcript.isEmpty {
            parts.append(transcript)
        }
        if !currentSegment.isEmpty {
            parts.append(currentSegment + " ⏳")
        }
        return parts.joined(separator: "\n\n")
    }
}
