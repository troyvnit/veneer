import AVFoundation
import UIKit

/// Records a voice clip for a composer: AAC in an .m4a file in the
/// temporary directory, with the input level sampled 20 times a second for
/// the waveform.
@available(iOS 26.0, *)
final class VoiceRecorder {
  enum Failure: String {
    /// The user declined (or earlier declined) microphone access.
    case permission
    /// The audio session or recorder couldn't start (e.g. no input route).
    case unavailable
  }

  var onSample: ((_ level: CGFloat, _ elapsed: TimeInterval) -> Void)?
  /// The clip reached its maximum duration.
  var onLimit: (() -> Void)?

  private var recorder: AVAudioRecorder?
  private var timer: Timer?
  private let maxDuration: TimeInterval?

  init(maxDuration: TimeInterval?) {
    self.maxDuration = maxDuration
  }

  /// Asks for microphone access if needed, then starts recording.
  func start(_ completion: @escaping (Failure?) -> Void) {
    AVAudioApplication.requestRecordPermission { granted in
      DispatchQueue.main.async {
        guard granted else { return completion(.permission) }
        completion(self.begin() ? nil : .unavailable)
      }
    }
  }

  private func begin() -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("voice-\(UUID().uuidString)")
        .appendingPathExtension("m4a")
      let recorder = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ])
      recorder.isMeteringEnabled = true
      guard recorder.record() else {
        deactivate()
        return false
      }
      self.recorder = recorder
    } catch {
      deactivate()
      return false
    }
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.sample() }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    return true
  }

  private func sample() {
    guard let recorder else { return }
    recorder.updateMeters()
    // -45 dB and below reads as silence (room noise stays dots); the curve
    // keeps quiet sound low so speech stands out from it.
    let power = recorder.averagePower(forChannel: 0)
    let level = CGFloat(pow(max(0, min(1, (power + 45) / 45)), 1.6))
    onSample?(level, recorder.currentTime)
    if let maxDuration, recorder.currentTime >= maxDuration { onLimit?() }
  }

  /// Stops and keeps the clip: its file and duration.
  func finish() -> (url: URL, duration: TimeInterval)? {
    guard let recorder else { return nil }
    let duration = recorder.currentTime
    stop()
    return (recorder.url, duration)
  }

  /// Stops and deletes the clip.
  func cancel() {
    let recorder = self.recorder
    stop()
    recorder?.deleteRecording()
  }

  private func stop() {
    timer?.invalidate()
    timer = nil
    recorder?.stop()
    recorder = nil
    deactivate()
  }

  private func deactivate() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

/// The composer's row while recording, as in Slack: cancel on the leading
/// edge, the live waveform, the elapsed time and a done button in the
/// accent colour where send sits.
@available(iOS 26.0, *)
final class RecordingBarView: UIView {
  var onCancel: (() -> Void)?
  var onDone: (() -> Void)?

  private let cancelButton = UIButton(configuration: .plain())
  private let doneButton = UIButton(configuration: .filled())
  private let waveform = WaveformView()
  private let timeLabel = UILabel()

  /// Centre of the edge buttons from the row's ends, and their size.
  var edgeCenter: CGFloat = 24
  var buttonSize: CGFloat = 32

  var accent: UIColor = .systemBlue {
    didSet {
      doneButton.configuration?.baseBackgroundColor = accent
      waveform.barColor = accent
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    cancelButton.configuration?.image = UIImage(systemName: "xmark")
    cancelButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 13, weight: .semibold)
    cancelButton.configuration?.baseForegroundColor = .label
    cancelButton.configuration?.background.backgroundColor = .tertiarySystemFill
    cancelButton.configuration?.cornerStyle = .capsule
    cancelButton.configuration?.contentInsets = .zero
    cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)

    doneButton.configuration?.image = UIImage(systemName: "checkmark")
    doneButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 15, weight: .semibold)
    doneButton.configuration?.baseForegroundColor = .white
    doneButton.configuration?.cornerStyle = .capsule
    doneButton.configuration?.contentInsets = .zero
    doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

    timeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    timeLabel.textColor = .label
    timeLabel.textAlignment = .right

    for v in [waveform, timeLabel, cancelButton, doneButton] as [UIView] { addSubview(v) }
    reset()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func setLabels(cancel: String?, done: String?) {
    cancelButton.accessibilityLabel = cancel
    doneButton.accessibilityLabel = done
  }

  func reset() {
    waveform.reset()
    setElapsed(0)
  }

  func append(level: CGFloat, elapsed: TimeInterval) {
    waveform.append(level)
    setElapsed(elapsed)
  }

  private func setElapsed(_ elapsed: TimeInterval) {
    let seconds = Int(elapsed)
    timeLabel.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width, h = bounds.height
    let s = buttonSize
    cancelButton.frame = CGRect(x: edgeCenter - s / 2, y: (h - s) / 2, width: s, height: s)
    doneButton.frame = CGRect(x: w - edgeCenter - s / 2, y: (h - s) / 2, width: s, height: s)
    let timeWidth = ceil(("0:00" as NSString).size(withAttributes: [.font: timeLabel.font!]).width) + 8
    timeLabel.frame = CGRect(x: doneButton.frame.minX - 12 - timeWidth, y: 0, width: timeWidth, height: h)
    let waveX = cancelButton.frame.maxX + 12
    waveform.frame = CGRect(x: waveX, y: (h - 24) / 2, width: max(0, timeLabel.frame.minX - 8 - waveX), height: 24)
  }
}

/// Levels scrolling in from the trailing edge: bars where there was sound,
/// dots where it was quiet and before the recording began.
@available(iOS 26.0, *)
final class WaveformView: UIView {
  var barColor: UIColor = .systemBlue {
    didSet { setNeedsDisplay() }
  }

  private var levels: [CGFloat] = []
  private static let barWidth: CGFloat = 3
  private static let step: CGFloat = 5
  private static let quiet: CGFloat = 0.08

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    contentMode = .redraw
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func reset() {
    levels.removeAll()
    setNeedsDisplay()
  }

  func append(_ level: CGFloat) {
    levels.append(level)
    let capacity = Int(bounds.width / Self.step) + 1
    if levels.count > max(capacity, 1) * 2 { levels.removeFirst(levels.count - max(capacity, 1)) }
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    let slots = Int(bounds.width / Self.step)
    guard slots > 0 else { return }
    let midY = bounds.midY
    let dotColor = UIColor.tertiaryLabel
    for slot in 0..<slots {
      let index = levels.count - slots + slot
      let x = bounds.width - CGFloat(slots - slot) * Self.step + (Self.step - Self.barWidth) / 2
      let level = index >= 0 ? levels[index] : 0
      if level < Self.quiet {
        dotColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: midY - Self.barWidth / 2, width: Self.barWidth, height: Self.barWidth)).fill()
      } else {
        barColor.setFill()
        let height = max(Self.barWidth, level * bounds.height)
        UIBezierPath(
          roundedRect: CGRect(x: x, y: midY - height / 2, width: Self.barWidth, height: height),
          cornerRadius: Self.barWidth / 2
        ).fill()
      }
    }
  }
}
