import Foundation
import AppKit
import Combine
import FoxCaptureCore

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var fps: Int {
        didSet { UserDefaults.standard.set(fps, forKey: "fps") }
    }
    @Published var codec: String {
        didSet { UserDefaults.standard.set(codec, forKey: "codec") }
    }
    @Published var showsCursor: Bool {
        didSet { UserDefaults.standard.set(showsCursor, forKey: "showsCursor") }
    }
    @Published var systemAudio: Bool {
        didSet { UserDefaults.standard.set(systemAudio, forKey: "systemAudio") }
    }
    @Published var micEnabled: Bool {
        didSet { UserDefaults.standard.set(micEnabled, forKey: "micEnabled") }
    }
    @Published var revealAfterRecording: Bool {
        didSet { UserDefaults.standard.set(revealAfterRecording, forKey: "revealAfterRecording") }
    }
    /// Pause automatically after `silenceSeconds` of silent system audio.
    @Published var pauseOnSilence: Bool {
        didSet { UserDefaults.standard.set(pauseOnSilence, forKey: "pauseOnSilence") }
    }
    /// What silence does when `pauseOnSilence` is on: "pause" or "stop".
    @Published var silenceAction: String {
        didSet { UserDefaults.standard.set(silenceAction, forKey: "silenceAction") }
    }
    /// Clicking Area reuses the previously selected rectangle.
    @Published var rememberLastArea: Bool {
        didSet { UserDefaults.standard.set(rememberLastArea, forKey: "rememberLastArea") }
    }
    /// Last area the user selected (not published: nothing in the UI shows it).
    var lastArea: RememberedArea? {
        get { RememberedArea.decode(UserDefaults.standard.data(forKey: "lastArea")) }
        set { UserDefaults.standard.set(newValue?.encoded(), forKey: "lastArea") }
    }
    static let silenceSeconds: TimeInterval = 4

    @Published var outputPath: String {
        didSet { UserDefaults.standard.set(outputPath, forKey: "outputPath") }
    }
    @Published var resolution: String {
        didSet { UserDefaults.standard.set(resolution, forKey: "resolution") }
    }

    // CPU re-encode after stop (ffmpeg): shrinks the file for uploading.
    @Published var reencodeEnabled: Bool {
        didSet { UserDefaults.standard.set(reencodeEnabled, forKey: "reencodeEnabled") }
    }
    @Published var reencodeResolution: String {
        didSet { UserDefaults.standard.set(reencodeResolution, forKey: "reencodeResolution") }
    }
    @Published var reencodeVideoCodec: String {
        didSet { UserDefaults.standard.set(reencodeVideoCodec, forKey: "reencodeVideoCodec") }
    }
    @Published var reencodeCRF: Int {
        didSet { UserDefaults.standard.set(reencodeCRF, forKey: "reencodeCRF") }
    }
    @Published var reencodeAudioCodec: String {
        didSet { UserDefaults.standard.set(reencodeAudioCodec, forKey: "reencodeAudioCodec") }
    }
    @Published var reencodeAudioKbps: Int {
        didSet { UserDefaults.standard.set(reencodeAudioKbps, forKey: "reencodeAudioKbps") }
    }
    /// Move the original recording to the Trash once the smaller file exists.
    @Published var reencodeDeleteOriginal: Bool {
        didSet { UserDefaults.standard.set(reencodeDeleteOriginal, forKey: "reencodeDeleteOriginal") }
    }

    /// The chosen re-encode settings, or nil while the option is off.
    var reencodeOptions: ReencodeOptions? {
        guard reencodeEnabled else { return nil }
        let defaults = ReencodeOptions()
        return ReencodeOptions(
            resolution: ReencodeOptions.Resolution(rawValue: reencodeResolution) ?? defaults.resolution,
            videoCodec: ReencodeOptions.VideoCodec(rawValue: reencodeVideoCodec) ?? defaults.videoCodec,
            crf: reencodeCRF,
            audioCodec: ReencodeOptions.AudioCodec(rawValue: reencodeAudioCodec) ?? defaults.audioCodec,
            audioBitrateKbps: reencodeAudioKbps
        )
    }

    /// ffmpeg is not bundled: it is looked for in the app bundle, Homebrew,
    /// MacPorts and PATH.
    static var ffmpegURL: URL? {
        FFmpegLocator.find(extraDirectories: [Bundle.main.resourceURL].compactMap { $0 })
    }

    // Mouse effects (visible in the video)
    @Published var highlightEnabled: Bool {
        didSet { UserDefaults.standard.set(highlightEnabled, forKey: "highlightEnabled") }
    }
    @Published var highlightColor: String {
        didSet { UserDefaults.standard.set(highlightColor, forKey: "highlightColor") }
    }
    @Published var highlightSize: Int {
        didSet { UserDefaults.standard.set(highlightSize, forKey: "highlightSize") }
    }
    @Published var highlightOpacity: Double {
        didSet { UserDefaults.standard.set(highlightOpacity, forKey: "highlightOpacity") }
    }
    @Published var clickEffectEnabled: Bool {
        didSet { UserDefaults.standard.set(clickEffectEnabled, forKey: "clickEffectEnabled") }
    }
    @Published var clickEffectSize: Int {
        didSet { UserDefaults.standard.set(clickEffectSize, forKey: "clickEffectSize") }
    }
    @Published var clickLeftColor: String {
        didSet { UserDefaults.standard.set(clickLeftColor, forKey: "clickLeftColor") }
    }
    @Published var clickRightColor: String {
        didSet { UserDefaults.standard.set(clickRightColor, forKey: "clickRightColor") }
    }
    @Published var clickSoundLeft: Bool {
        didSet { UserDefaults.standard.set(clickSoundLeft, forKey: "clickSoundLeft") }
    }
    @Published var clickSoundRight: Bool {
        didSet { UserDefaults.standard.set(clickSoundRight, forKey: "clickSoundRight") }
    }
    @Published var webcamOverlay: Bool {
        didSet { UserDefaults.standard.set(webcamOverlay, forKey: "webcamOverlay") }
    }
    @Published var webcamBubbleSize: Int {
        didSet { UserDefaults.standard.set(webcamBubbleSize, forKey: "webcamBubbleSize") }
    }
    @Published var hotKeyKeyCode: Int {
        didSet { UserDefaults.standard.set(hotKeyKeyCode, forKey: "hotKeyKeyCode") }
    }
    @Published var hotKeyModifiers: Int {
        didSet { UserDefaults.standard.set(hotKeyModifiers, forKey: "hotKeyModifiers") }
    }
    @Published var hotKeyAction: String {
        didSet { UserDefaults.standard.set(hotKeyAction, forKey: "hotKeyAction") }
    }

    var hotKeyDisplay: String {
        guard hotKeyKeyCode >= 0 else { return "Click to set shortcut" }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(hotKeyModifiers))
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + KeyCodeNames.name(for: hotKeyKeyCode)
    }

    static let colorNames = ["yellow", "pink", "green", "red", "blue", "orange"]

    static func color(named name: String) -> NSColor {
        switch name {
        case "pink": return .systemPink
        case "green": return .systemGreen
        case "red": return .systemRed
        case "blue": return .systemBlue
        case "orange": return .systemOrange
        default: return .systemYellow
        }
    }

    /// Output scale in pixels-per-point for the chosen resolution setting.
    func effectiveScale(pointPixelScale: CGFloat) -> CGFloat {
        switch resolution {
        case "standard": return 1.0
        case "half": return 0.5
        default: return pointPixelScale // native Retina
        }
    }

    var outputDirectory: URL {
        if !outputPath.isEmpty {
            return URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoxCapture")
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "fps": 60,
            "codec": "h264",
            "showsCursor": true,
            "systemAudio": true,
            "micEnabled": false,
            "revealAfterRecording": true,
            "pauseOnSilence": false,
            "silenceAction": "pause",
            "rememberLastArea": false,
            "outputPath": "",
            "resolution": "native",
            "reencodeEnabled": false,
            "reencodeResolution": "1080p",
            "reencodeVideoCodec": "x265",
            "reencodeCRF": 28,
            "reencodeAudioCodec": "aac",
            "reencodeAudioKbps": 32,
            "reencodeDeleteOriginal": false,
            "highlightEnabled": true,
            "highlightColor": "yellow",
            "highlightSize": 100,
            "highlightOpacity": 25.0,
            "clickEffectEnabled": true,
            "clickEffectSize": 100,
            "clickLeftColor": "green",
            "clickRightColor": "red",
            "clickSoundLeft": false,
            "clickSoundRight": false,
            "webcamOverlay": false,
            "webcamBubbleSize": 220,
            "hotKeyKeyCode": -1,
            "hotKeyModifiers": 0,
            "hotKeyAction": "screen"
        ])
        fps = defaults.integer(forKey: "fps")
        codec = defaults.string(forKey: "codec") ?? "h264"
        showsCursor = defaults.bool(forKey: "showsCursor")
        systemAudio = defaults.bool(forKey: "systemAudio")
        micEnabled = defaults.bool(forKey: "micEnabled")
        revealAfterRecording = defaults.bool(forKey: "revealAfterRecording")
        pauseOnSilence = defaults.bool(forKey: "pauseOnSilence")
        silenceAction = defaults.string(forKey: "silenceAction") ?? "pause"
        rememberLastArea = defaults.bool(forKey: "rememberLastArea")
        outputPath = defaults.string(forKey: "outputPath") ?? ""
        resolution = defaults.string(forKey: "resolution") ?? "native"
        reencodeEnabled = defaults.bool(forKey: "reencodeEnabled")
        reencodeResolution = defaults.string(forKey: "reencodeResolution") ?? "1080p"
        reencodeVideoCodec = defaults.string(forKey: "reencodeVideoCodec") ?? "x265"
        reencodeCRF = defaults.integer(forKey: "reencodeCRF")
        reencodeAudioCodec = defaults.string(forKey: "reencodeAudioCodec") ?? "aac"
        reencodeAudioKbps = defaults.integer(forKey: "reencodeAudioKbps")
        reencodeDeleteOriginal = defaults.bool(forKey: "reencodeDeleteOriginal")
        highlightEnabled = defaults.bool(forKey: "highlightEnabled")
        highlightColor = defaults.string(forKey: "highlightColor") ?? "yellow"
        highlightSize = defaults.integer(forKey: "highlightSize")
        highlightOpacity = defaults.double(forKey: "highlightOpacity")
        clickEffectEnabled = defaults.bool(forKey: "clickEffectEnabled")
        clickEffectSize = defaults.integer(forKey: "clickEffectSize")
        clickLeftColor = defaults.string(forKey: "clickLeftColor") ?? "green"
        clickRightColor = defaults.string(forKey: "clickRightColor") ?? "red"
        clickSoundLeft = defaults.bool(forKey: "clickSoundLeft")
        clickSoundRight = defaults.bool(forKey: "clickSoundRight")
        webcamOverlay = defaults.bool(forKey: "webcamOverlay")
        webcamBubbleSize = defaults.integer(forKey: "webcamBubbleSize")
        hotKeyKeyCode = defaults.object(forKey: "hotKeyKeyCode") as? Int ?? -1
        hotKeyModifiers = defaults.integer(forKey: "hotKeyModifiers")
        hotKeyAction = defaults.string(forKey: "hotKeyAction") ?? "screen"
    }
}
