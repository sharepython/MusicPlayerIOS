import AVFoundation
import Speech

/// 在线查不到时，用本机语音识别把歌声转成带时间轴的歌词。
/// 用 iOS 26 的 SpeechAnalyzer，全程在手机上离线完成；伴奏会干扰识别，结果可能有错字
enum LyricsRecognizer {
    /// iOS 26 以下没有 SpeechAnalyzer，不做识别
    static var supported: Bool {
        if #available(iOS 26, *) {
            true
        } else {
            false
        }
    }

    /// 用户还没回答过语音识别授权
    static var notAsked: Bool { SFSpeechRecognizer.authorizationStatus() == .notDetermined }

    /// 弹系统授权框。只在用户打开歌词页、点了按钮时调用，不在后台突然弹
    static func requestPermission() async {
        guard notAsked else { return }
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { _ in c.resume() } }
    }

    /// 没授权或识别不出来时返回 nil
    static func recognize(_ song: Song) async -> [Lyrics.Line]? {
        guard #available(iOS 26, *), SFSpeechRecognizer.authorizationStatus() == .authorized else { return nil }
        return try? await transcribe(song)
    }

    @available(iOS 26, *)
    private static func transcribe(_ song: Song) async throws -> [Lyrics.Line]? {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language(of: song)) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        // 第一次识别某种语言时，系统会下载对应的识别模型
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: song.fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task {
            var lines: [Lyrics.Line] = []
            for try await r in transcriber.results { lines += split(r.text) }
            return lines
        }
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let lines = try await collect.value
        return lines.isEmpty ? nil : lines
    }

    /// 一段识别结果拆成歌词行：遇到标点、停顿超过 0.6 秒或一行够长时换行，标点不保留
    @available(iOS 26, *)
    private static func split(_ text: AttributedString) -> [Lyrics.Line] {
        let punctuation = CharacterSet(charactersIn: "，。！？、；：,.!?;:")
        var lines: [Lyrics.Line] = []
        var current = "", start: Double?, lastEnd = 0.0
        func flush() {
            let t = current.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                lines.append(Lyrics.Line(time: start, text: t))
            }
            current = ""; start = nil
        }
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let range = run.audioTimeRange
            let begin = range?.start.seconds ?? lastEnd
            let cjk = current.unicodeScalars.contains { $0.value >= 0x2E80 }
            if !current.isEmpty, begin - lastEnd > 0.6 || current.count >= (cjk ? 14 : 36) {
                flush()
            }
            if start == nil {
                start = begin
            }
            current += piece.components(separatedBy: punctuation).joined(separator: " ")
            if let range {
                lastEnd = range.end.seconds
            }
            if piece.unicodeScalars.last.map(punctuation.contains) == true {
                flush()
            }
        }
        flush()
        return lines
    }

    /// 按歌名、歌手里的文字猜演唱语言
    private static func language(of song: Song) -> Locale {
        let s = (song.title + song.artist).unicodeScalars
        if s.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) {
            return Locale(identifier: "ko-KR")
        }
        if s.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return Locale(identifier: "ja-JP")
        }
        if s.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return Locale(identifier: "zh-CN")
        }
        return Locale(identifier: "en-US")
    }
}
