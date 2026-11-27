import Foundation

/// What "CPU Re-encode after stop" should do to a finished recording.
public struct ReencodeOptions: Equatable {
    public enum Resolution: String, CaseIterable {
        case original
        case p1080 = "1080p"
        case p720 = "720p"

        /// Height cap in pixels; nil keeps the recorded size.
        public var maxHeight: Int? {
            switch self {
            case .original: return nil
            case .p1080: return 1080
            case .p720: return 720
            }
        }
    }

    public enum VideoCodec: String, CaseIterable {
        case x265
        case x264

        public var encoder: String { self == .x265 ? "libx265" : "libx264" }
    }

    public enum AudioCodec: String, CaseIterable {
        case opus
        case aac

        public var encoder: String { self == .opus ? "libopus" : "aac" }
    }

    /// Speed/size trade-off for both video encoders.
    public static let preset = "medium"

    public var resolution: Resolution
    public var videoCodec: VideoCodec
    /// Constant Rate Factor: lower is better quality and a bigger file.
    public var crf: Int
    public var audioCodec: AudioCodec
    public var audioBitrateKbps: Int

    public init(
        resolution: Resolution = .p1080,
        videoCodec: VideoCodec = .x265,
        crf: Int = 28,
        audioCodec: AudioCodec = .aac,
        audioBitrateKbps: Int = 32
    ) {
        self.resolution = resolution
        self.videoCodec = videoCodec
        self.crf = crf
        self.audioCodec = audioCodec
        self.audioBitrateKbps = audioBitrateKbps
    }

    /// The ffmpeg command line (without the executable). Progress is reported
    /// on stdout as key=value lines; everything else is quiet.
    public func arguments(input: URL, output: URL) -> [String] {
        var args = [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-i", input.path,
            // First video track plus every audio track (the "?" tolerates
            // recordings without audio).
            "-map", "0:v:0", "-map", "0:a?"
        ]

        if let height = resolution.maxHeight {
            // Cap the height without ever upscaling; -2 keeps the aspect
            // ratio and an even width.
            args += ["-vf", "scale=-2:'min(\(height),ih)':flags=lanczos"]
        }

        args += [
            "-c:v", videoCodec.encoder,
            "-preset", Self.preset,
            "-crf", String(crf),
            "-pix_fmt", "yuv420p"
        ]
        if videoCodec == .x265 {
            // hvc1 is the tag QuickTime and YouTube expect for HEVC in MP4.
            args += ["-tag:v", "hvc1", "-x265-params", "log-level=error"]
        }

        args += [
            "-c:a", audioCodec.encoder,
            "-b:a", "\(audioBitrateKbps)k",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            // Explicit, because the output is written to a ".part" file first.
            "-f", "mp4",
            output.path
        ]
        return args
    }
}

/// Reads ffmpeg's `-progress pipe:1` output, which arrives in arbitrary chunks.
public struct FFmpegProgressParser {
    private var pending = Data()
    /// Encoded media time so far, in seconds.
    public private(set) var seconds: Double?

    public init() {}

    public mutating func feed(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
            pending = Data(pending[(newline + 1)...])
            handle(line: line)
        }
    }

    /// Fraction done (0...1) for a source of the given length.
    public func fraction(of duration: TimeInterval) -> Double? {
        guard let seconds, duration > 0 else { return nil }
        return min(1, max(0, seconds / duration))
    }

    private mutating func handle(line: String) {
        guard let equals = line.firstIndex(of: "=") else { return }
        let key = String(line[..<equals])
        let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        // Despite its name, out_time_ms is microseconds too (a long-standing
        // ffmpeg quirk), so both keys are divided by a million. "N/A" and
        // negative values appear before the first frame and are ignored.
        guard key == "out_time_us" || key == "out_time_ms",
              let micro = Double(value), micro >= 0 else { return }
        seconds = micro / 1_000_000
    }
}

/// Finds an ffmpeg binary. A menu bar app doesn't inherit the shell's PATH,
/// so Homebrew and MacPorts locations are checked explicitly.
public enum FFmpegLocator {
    public static let commonDirectories = [
        "/opt/homebrew/bin",   // Homebrew on Apple silicon
        "/usr/local/bin",      // Homebrew on Intel
        "/opt/local/bin",      // MacPorts
        "/usr/bin"
    ]

    public static func find(
        extraDirectories: [URL] = [],
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        fileManager: FileManager = .default
    ) -> URL? {
        var directories = extraDirectories.map(\.path)
        directories += commonDirectories
        directories += (path ?? "").split(separator: ":").map(String.init)
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("ffmpeg")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// Runs one ffmpeg re-encode, reporting progress, and writes the result to a
/// temporary ".part" file that only becomes the final file on success.
public final class Reencoder {
    public enum Outcome {
        case finished(URL)
        case cancelled
        case failed(String)
    }

    public let output: URL
    private let ffmpeg: URL
    private let input: URL
    private let partial: URL
    private let options: ReencodeOptions
    private let process = Process()
    private let lock = NSLock()
    private var cancelRequested = false
    private var didLaunch = false
    private var parser = FFmpegProgressParser()
    private var errorTail = Data()

    public init(ffmpeg: URL, input: URL, output: URL, options: ReencodeOptions) {
        self.ffmpeg = ffmpeg
        self.input = input
        self.output = output
        self.partial = output.appendingPathExtension("part")
        self.options = options
    }

    /// "<name> (compressed).mp4" next to the original, numbered if taken.
    public static func outputURL(for input: URL, fileManager: FileManager = .default) -> URL {
        let folder = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent("\(base) (compressed).mp4")
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (compressed \(number)).mp4")
            number += 1
        }
        return candidate
    }

    /// Starts ffmpeg. `onProgress` (0...1) and `completion` are called on
    /// background threads; `onProgress` never fires when `duration` is unknown.
    public func start(
        duration: TimeInterval?,
        onProgress: @escaping (Double) -> Void,
        completion: @escaping (Outcome) -> Void
    ) {
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = ffmpeg
        process.arguments = options.arguments(input: input, output: partial)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        // Keep the Mac and the menu bar responsive while x265 uses every core.
        process.qualityOfService = .utility

        // At end-of-file a readability handler keeps firing with empty data,
        // so each one removes itself then.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.consumeProgress(data, duration: duration, onProgress: onProgress)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.consumeError(data)
        }
        process.terminationHandler = { [weak self] finished in
            self?.processDidExit(status: finished.terminationStatus, stdout: stdout, stderr: stderr, completion: completion)
        }

        try? FileManager.default.removeItem(at: partial)

        // Launch and cancel share the lock so a cancel can never slip in
        // between the check and the launch.
        lock.lock()
        if cancelRequested {
            lock.unlock()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            completion(.cancelled)
            return
        }
        var launchError: Error?
        do {
            try process.run()
            didLaunch = true
        } catch {
            launchError = error
        }
        lock.unlock()

        if let launchError {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            completion(.failed("Could not start ffmpeg: \(launchError.localizedDescription)"))
        }
    }

    /// Stops ffmpeg; `completion` then reports `.cancelled` and the partial
    /// file is removed. Safe to call before `start`.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelRequested = true
        if process.isRunning {
            process.terminate()
        }
    }

    /// Like `cancel`, but returns only once ffmpeg is gone (for app quit).
    public func cancelAndWait() {
        cancel()
        lock.lock()
        let launched = didLaunch
        lock.unlock()
        if launched {
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: partial)
    }

    // MARK: - Process I/O

    private func consumeProgress(_ data: Data, duration: TimeInterval?, onProgress: (Double) -> Void) {
        lock.lock()
        parser.feed(data)
        let fraction = duration.flatMap { parser.fraction(of: $0) }
        lock.unlock()
        if let fraction {
            onProgress(fraction)
        }
    }

    private func consumeError(_ data: Data) {
        lock.lock()
        errorTail.append(data)
        if errorTail.count > 4096 {
            errorTail = Data(errorTail.suffix(4096))
        }
        lock.unlock()
    }

    private func processDidExit(status: Int32, stdout: Pipe, stderr: Pipe, completion: (Outcome) -> Void) {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        // Whatever ffmpeg wrote last may still be unread.
        if let rest = try? stderr.fileHandleForReading.readToEnd() {
            consumeError(rest)
        }

        lock.lock()
        let wasCancelled = cancelRequested
        let tail = errorTail
        lock.unlock()

        let fileManager = FileManager.default
        if wasCancelled {
            try? fileManager.removeItem(at: partial)
            completion(.cancelled)
            return
        }
        guard status == 0 else {
            try? fileManager.removeItem(at: partial)
            completion(.failed(Self.message(from: tail, status: status)))
            return
        }
        do {
            try fileManager.moveItem(at: partial, to: output)
            completion(.finished(output))
        } catch {
            try? fileManager.removeItem(at: partial)
            completion(.failed(error.localizedDescription))
        }
    }

    static func message(from tail: Data, status: Int32) -> String {
        let lines = String(decoding: tail, as: UTF8.self)
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.isEmpty {
            return "ffmpeg exited with code \(status)"
        }
        return lines.suffix(2).joined(separator: " ")
    }
}
