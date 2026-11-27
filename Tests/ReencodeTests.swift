import XCTest
@testable import FoxCaptureCore

final class ReencodeOptionsTests: XCTestCase {
    private let input = URL(fileURLWithPath: "/tmp/in.mp4")
    private let output = URL(fileURLWithPath: "/tmp/out.mp4.part")

    func testDefaultsAreSmallFileSettings() {
        let options = ReencodeOptions()
        XCTAssertEqual(options.resolution, .p1080)
        XCTAssertEqual(options.videoCodec, .x265)
        XCTAssertEqual(options.crf, 28)
        XCTAssertEqual(options.audioCodec, .aac)
        XCTAssertEqual(options.audioBitrateKbps, 32)
    }

    func testX265With720pAndOpus() {
        let options = ReencodeOptions(resolution: .p720, videoCodec: .x265, crf: 28, audioCodec: .opus, audioBitrateKbps: 16)
        XCTAssertEqual(options.arguments(input: input, output: output), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-i", "/tmp/in.mp4",
            "-map", "0:v:0", "-map", "0:a?",
            "-vf", "scale=-2:'min(720,ih)':flags=lanczos",
            "-c:v", "libx265", "-preset", "medium", "-crf", "28", "-pix_fmt", "yuv420p",
            "-tag:v", "hvc1", "-x265-params", "log-level=error",
            "-c:a", "libopus", "-b:a", "16k",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            "-f", "mp4",
            "/tmp/out.mp4.part"
        ])
    }

    func testX264OriginalSizeHasNoScaleFilterAndNoHevcTag() {
        let options = ReencodeOptions(resolution: .original, videoCodec: .x264, crf: 23, audioCodec: .aac, audioBitrateKbps: 192)
        let args = options.arguments(input: input, output: output)
        XCTAssertFalse(args.contains("-vf"))
        XCTAssertFalse(args.contains("-tag:v"))
        XCTAssertFalse(args.contains("-x265-params"))
        XCTAssertEqual(value(after: "-c:v", in: args), "libx264")
        XCTAssertEqual(value(after: "-crf", in: args), "23")
        XCTAssertEqual(value(after: "-c:a", in: args), "aac")
        XCTAssertEqual(value(after: "-b:a", in: args), "192k")
    }

    func testOutputDurationAddsTimeLimitBeforeEncoderOptions() {
        let args = ReencodeOptions().arguments(input: input, output: output, outputDuration: 17)
        XCTAssertEqual(value(after: "-t", in: args), "17.000")
        XCTAssertLessThan(args.firstIndex(of: "-t")!, args.firstIndex(of: "-c:v")!)
        XCTAssertFalse(ReencodeOptions().arguments(input: input, output: output).contains("-t"))
    }

    func testTrimmedDurationRules() {
        XCTAssertEqual(Reencoder.trimmedDuration(of: 60, trimEnd: 3), 57)
        XCTAssertEqual(Reencoder.trimmedDuration(of: 60, trimEnd: 13), 47)
        XCTAssertNil(Reencoder.trimmedDuration(of: 60, trimEnd: 0))
        XCTAssertNil(Reencoder.trimmedDuration(of: nil, trimEnd: 8))
        XCTAssertNil(Reencoder.trimmedDuration(of: 8.5, trimEnd: 8))
    }

    func testResolutionNeverUpscales() {
        let args = ReencodeOptions(resolution: .p1080).arguments(input: input, output: output)
        XCTAssertEqual(value(after: "-vf", in: args), "scale=-2:'min(1080,ih)':flags=lanczos")
    }

    func testPathsWithSpacesStayOneArgument() {
        let spaced = URL(fileURLWithPath: "/Users/me/Movies/FoxCapture/FoxCapture 2026-11-26 at 10.00.00.mp4")
        let args = ReencodeOptions().arguments(input: spaced, output: output)
        XCTAssertEqual(value(after: "-i", in: args), spaced.path)
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

final class FFmpegProgressParserTests: XCTestCase {
    func testReadsOutTimeFromAWholeBlock() {
        var parser = FFmpegProgressParser()
        parser.feed(Data("frame=10\nout_time_us=2500000\nout_time_ms=2500000\nout_time=00:00:02.500000\nprogress=continue\n".utf8))
        XCTAssertEqual(parser.seconds, 2.5)
        XCTAssertEqual(parser.fraction(of: 10), 0.25)
    }

    func testHandlesLinesSplitAcrossChunks() {
        var parser = FFmpegProgressParser()
        parser.feed(Data("out_time_us=12".utf8))
        XCTAssertNil(parser.seconds)
        parser.feed(Data("00000\nprogress=con".utf8))
        XCTAssertEqual(parser.seconds, 1.2)
        parser.feed(Data("tinue\n".utf8))
        XCTAssertEqual(parser.seconds, 1.2)
    }

    func testIgnoresNotAvailableAndNegativeValues() {
        var parser = FFmpegProgressParser()
        parser.feed(Data("out_time_us=N/A\nout_time_ms=-9223372036854775807\n".utf8))
        XCTAssertNil(parser.seconds)
    }

    func testFractionIsClampedAndNeedsADuration() {
        var parser = FFmpegProgressParser()
        parser.feed(Data("out_time_us=9000000\n".utf8))
        XCTAssertEqual(parser.fraction(of: 6), 1)
        XCTAssertNil(parser.fraction(of: 0))
    }
}

final class ReencoderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("foxcapture-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testOutputURLSitsNextToTheOriginal() {
        let input = directory.appendingPathComponent("FoxCapture 2026-11-26 at 10.00.00.mp4")
        XCTAssertEqual(
            Reencoder.outputURL(for: input),
            directory.appendingPathComponent("FoxCapture 2026-11-26 at 10.00.00 (compressed).mp4")
        )
    }

    func testOutputURLNumbersWhenTaken() throws {
        let input = directory.appendingPathComponent("clip.mov")
        FileManager.default.createFile(atPath: directory.appendingPathComponent("clip (compressed).mp4").path, contents: Data())
        XCTAssertEqual(
            Reencoder.outputURL(for: input),
            directory.appendingPathComponent("clip (compressed 2).mp4")
        )
    }

    func testLocatorFindsExecutableInExtraDirectoryAndSkipsNonExecutables() throws {
        let binary = directory.appendingPathComponent("ffmpeg")
        FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))

        // Not executable yet: it must not be returned (a system ffmpeg
        // elsewhere may be, so only compare against this file).
        XCTAssertNotEqual(FFmpegLocator.find(extraDirectories: [directory], path: "")?.path, binary.path)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        XCTAssertEqual(
            FFmpegLocator.find(extraDirectories: [directory], path: "")?.path,
            binary.path
        )
    }

    func testErrorMessageUsesTheLastLinesOfStderr() {
        let tail = Data("noise\nUnknown encoder 'libx265'\n\n".utf8)
        XCTAssertEqual(Reencoder.message(from: tail, status: 1), "noise Unknown encoder 'libx265'")
        XCTAssertEqual(Reencoder.message(from: Data(), status: 7), "ffmpeg exited with code 7")
    }
}
