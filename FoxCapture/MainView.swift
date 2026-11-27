import SwiftUI
import AppKit
import FoxCaptureCore

struct MainView: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var settings = AppSettings.shared
    @State private var isShowingSettings = false

    var body: some View {
        if isShowingSettings {
            SettingsView(controller: controller, isShowingSettings: $isShowingSettings)
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            recordSection
            Divider()
            historySection
        }
        .frame(width: 380, height: 500)
    }

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 13, weight: .semibold))
            Text("FoxCapture2")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { isShowingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var recordSection: some View {
        VStack(spacing: 10) {
            if let title = controller.pendingTitle {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Cancel") { controller.cancelPending() }
                        .keyboardShortcut(.cancelAction)
                    Button(action: { controller.confirmStart() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle")
                            Text("Start")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                }
                .font(.system(size: 12))
            } else if controller.state == .recording || controller.state == .paused {
                HStack(spacing: 8) {
                    Button(action: {
                        controller.state == .paused ? controller.resume() : controller.pause()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: controller.state == .paused ? "play.fill" : "pause.fill")
                            Text(controller.state == .paused ? "Continue" : "Pause")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { controller.stop() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop  \(AppDelegate.format(controller.elapsed))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 8) {
                    Button(action: { controller.recordArea() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "rectangle.dashed")
                            Text("Area")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.state != .idle)

                    Button(action: { controller.recordFullScreen() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "display")
                            Text("Screen")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.state != .idle)

                    Button(action: { controller.recordWebcam() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "camera")
                            Text("Webcam")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.state != .idle)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Toggle("System Audio", isOn: $settings.systemAudio)
                    Toggle("Microphone", isOn: $settings.micEnabled)
                    Spacer()
                }
                HStack(spacing: 14) {
                    Toggle("Cursor", isOn: $settings.showsCursor)
                    Toggle("Webcam bubble", isOn: $settings.webcamOverlay)
                    Spacer()
                }
                HStack(spacing: 14) {
                    Toggle("Remember last area", isOn: $settings.rememberLastArea)
                    Toggle("On silence:", isOn: $settings.pauseOnSilence)
                        .help("After \(settings.silenceSeconds) seconds without system audio, pause or stop the recording")
                    Picker("", selection: $settings.silenceAction) {
                        Text("Pause").tag("pause")
                        Text("Stop").tag("stop")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .disabled(!settings.pauseOnSilence)
                    Spacer()
                }
            }
            .font(.system(size: 11))
            .toggleStyle(.checkbox)
            .disabled(controller.state != .idle)

            // Not disabled while recording: the choice is read when you stop.
            HStack(spacing: 14) {
                Toggle("CPU Re-encode after stop", isOn: $settings.reencodeEnabled)
                    .help("Shrink the recording with ffmpeg after you stop. Choose the quality in Settings.")
                Spacer()
            }
            .font(.system(size: 11))
            .toggleStyle(.checkbox)
            .disabled(controller.state == .encoding)

            if controller.state == .paused, let reason = controller.pauseReason {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if controller.state == .selecting {
                Text("Drag to select an area on any screen. Esc cancels.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if controller.state == .confirming, controller.pendingTitle == nil {
                Text("Confirm in the panel next to your selection: Start Recording, Reselect or Cancel (Esc).")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if controller.state == .finishing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finalizing video…")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            if controller.state == .encoding {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(controller.encodeProgress.map { "Re-encoding… \(Int(($0 * 100).rounded()))%" } ?? "Re-encoding…")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button("Cancel") { controller.cancelReencode() }
                            .controlSize(.small)
                    }
                    if let progress = controller.encodeProgress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text("The original recording is kept until the smaller file is ready.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            if let info = controller.infoMessage {
                Text(info)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recordings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { NSWorkspace.shared.open(settings.outputDirectory) }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Open recordings folder")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if controller.captures.isEmpty {
                Text("No recordings yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.captures) { capture in
                            CaptureRow(
                                capture: capture,
                                onDelete: { controller.delete(capture) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct CaptureRow: View {
    let capture: Capture
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: capture.createdAt))
                    .font(.system(size: 11, weight: .medium))
                Text(ByteCountFormatter.string(fromByteCount: capture.fileSize, countStyle: .file))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { NSWorkspace.shared.open(capture.url) }) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .help("Play")

            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([capture.url]) }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .help("Reveal in Finder")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .help("Move to Trash")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
