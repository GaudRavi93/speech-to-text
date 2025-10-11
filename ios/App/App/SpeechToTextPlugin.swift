import Capacitor
import Speech
import AVFoundation
import Foundation

@objc(SpeechToTextPlugin)
public class SpeechToTextPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SpeechToTextPlugin"
    public let jsName = "SpeechToText"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getSupportedLanguages", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDownloadedLanguageModels", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "downloadLanguageModel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startRecognition", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecognition", returnType: CAPPluginReturnPromise)
    ]
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var isRecording = false
    private var currentLanguage = "en-US"
    
    // Supported languages mapping to locale identifiers
    private let supportedLanguages: [String: String] = [
        "en-us": "en-US",
        "de": "de-DE",
        "fr": "fr-FR",
        "es": "es-ES",
        "pt": "pt-PT",
        "zh": "zh-CN",
        "ru": "ru-RU",
        "tr": "tr-TR",
        "vi": "vi-VN",
        "it": "it-IT",
        "hi": "hi-IN",
        "gu": "gu-IN",
        "te": "te-IN",
        "ja": "ja-JP",
        "ko": "ko-KR"
    ]
    
    // Language names mapping
    private let languageNames: [String: String] = [
        "en-us": "English (US)",
        "de": "German",
        "fr": "French",
        "es": "Spanish",
        "pt": "Portuguese",
        "zh": "Chinese",
        "ru": "Russian",
        "tr": "Turkish",
        "vi": "Vietnamese",
        "it": "Italian",
        "hi": "Hindi",
        "gu": "Gujarati",
        "te": "Telugu",
        "ja": "Japanese",
        "ko": "Korean"
    ]
    
    override public func load() {
        super.load()
        requestSpeechRecognitionPermission()
    }
    
    // MARK: - Plugin Methods
    
    @objc func getSupportedLanguages(_ call: CAPPluginCall) {
        var languages: [[String: Any]] = []
        
        for (code, locale) in supportedLanguages {
            let isAvailable = isLanguageModelAvailable(locale: locale)
            let isOfflineSupported = isOfflineSupported(locale: locale)
            
            if isAvailable {
                let language: [String: Any] = [
                    "code": code,
                    "modelName": "model-\(code)",
                    "name": languageNames[code] ?? code,
                    "offlineSupported": isOfflineSupported
                ]
                languages.append(language)
            }
        }
        
        call.resolve(["languages": languages])
    }
    
    @objc func getDownloadedLanguageModels(_ call: CAPPluginCall) {
        var models: [[String: Any]] = []
        
        for (code, locale) in supportedLanguages {
            if isLanguageModelAvailable(locale: locale) {
                let isOfflineSupported = isOfflineSupported(locale: locale)
                let model: [String: Any] = [
                    "modelName": "model-\(code)",
                    "language": code,
                    "name": languageNames[code] ?? code,
                    "size": getModelSize(for: code),
                    "offlineSupported": isOfflineSupported
                ]
                models.append(model)
            }
        }
        
        call.resolve(["models": models])
    }
    
    @objc func downloadLanguageModel(_ call: CAPPluginCall) {
        guard let language = call.getString("language") else {
            call.reject("Language parameter is required")
            return
        }
        
        guard let locale = supportedLanguages[language] else {
            call.reject("Unsupported language: \(language)")
            return
        }
        
        // Check if model is already available
        if isLanguageModelAvailable(locale: locale) {
            call.resolve([
                "success": true,
                "language": language,
                "message": "Model already available"
            ])
            return
        }
        
        // For iOS, we check if the language is supported
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            call.reject("Language not supported by iOS Speech framework")
            return
        }
        
        guard recognizer.isAvailable else {
            call.reject("Language not available on this device")
            return
        }
        
        let isOfflineSupported = isOfflineSupported(locale: locale)
        let message = isOfflineSupported ? 
            "Language supported for offline recognition" : 
            "Language supported (requires internet connection)"
        
        call.resolve([
            "success": true,
            "language": language,
            "message": message,
            "offlineSupported": isOfflineSupported
        ])
    }
    
    @objc func startRecognition(_ call: CAPPluginCall) {
        let language = call.getString("language", "en-us")
        
        guard let locale = supportedLanguages[language] else {
            call.reject("Unsupported language: \(language)")
            return
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            call.reject("Language not supported by iOS Speech framework")
            return
        }
        
        guard recognizer.isAvailable else {
            call.reject("Language not available on this device")
            return
        }
        
        // Check permissions
        guard checkPermissions() else {
            call.reject("Microphone permission is required")
            return
        }
        
        startSpeechRecognition(locale: locale, language: language)
        call.resolve()
    }
    
    @objc func stopRecognition(_ call: CAPPluginCall) {
        stopSpeechRecognition()
        call.resolve()
    }
    
    // MARK: - Private Methods
    
    private func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied:
                    print("Speech recognition denied")
                case .restricted:
                    print("Speech recognition restricted")
                case .notDetermined:
                    print("Speech recognition not determined")
                @unknown default:
                    print("Speech recognition unknown status")
                }
            }
        }
    }
    
    private func checkPermissions() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        switch audioSession.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            audioSession.requestRecordPermission { granted in
                // Permission result handled asynchronously
            }
            return false
        @unknown default:
            return false
        }
    }
    
    private func isLanguageModelAvailable(locale: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            return false
        }
        
        // Check if the language is supported (either offline or online)
        return recognizer.isAvailable
    }
    
    private func isOfflineSupported(locale: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            return false
        }
        
        // Check if on-device recognition is supported
        if #available(iOS 13.0, *) {
            return recognizer.supportsOnDeviceRecognition
        } else {
            // For iOS 12 and below, assume offline is not supported
            return false
        }
    }
    
    private func getModelSize(for language: String) -> Int {
        // iOS doesn't download models locally, so we return 0
        return 0
    }
    
    private func startSpeechRecognition(locale: String, language: String) {
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            print("Speech recognizer not available for locale: \(locale)")
            return
        }
        
        // Check if on-device recognition is supported for this locale
        let supportsOffline = isOfflineSupported(locale: locale)
        if !supportsOffline {
            print("On-device recognition not supported for locale: \(locale), will use online recognition")
        }
        
        guard speechRecognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }
        
        self.speechRecognizer = speechRecognizer
        self.currentLanguage = language
        
        // Cancel any previous recognition task
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // Create audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Force on-device recognition only if supported
        if #available(iOS 13.0, *) {
            if supportsOffline {
                recognitionRequest.requiresOnDeviceRecognition = true
                print("Using offline recognition for locale: \(locale)")
            } else {
                print("Using online recognition for locale: \(locale)")
            }
        }
        
        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("Unable to create audio engine")
            return
        }
        
        let inputNode = audioEngine.inputNode
        
        // Configure recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                // Notify listeners with recognition result
                self?.notifyListeners("recognitionResult", data: [
                    "text": text,
                    "isFinal": isFinal,
                    "language": self?.currentLanguage ?? language
                ])
            }
            
            if error != nil || isFinal {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                self?.isRecording = false
            }
        }
        
        // Configure audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("Audio engine start failed: \(error)")
        }
    }
    
    private func stopSpeechRecognition() {
        if let audioEngine = audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation failed: \(error)")
        }
    }
    
    deinit {
        stopSpeechRecognition()
    }
}