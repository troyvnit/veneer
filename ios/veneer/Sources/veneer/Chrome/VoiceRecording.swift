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
  private var elapsed: TimeInterval = 0
  private(set) var isPaused = false

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
    startTimer()
    return true
  }

  private func startTimer() {
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.sample() }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// Holds the clip open without recording; the waveform and time stop.
  func pause() {
    guard let recorder, !isPaused else { return }
    elapsed = recorder.currentTime
    recorder.pause()
    timer?.invalidate()
    timer = nil
    isPaused = true
  }

  /// Carries on recording into the same clip.
  func resume() {
    guard let recorder, isPaused, recorder.record() else { return }
    isPaused = false
    startTimer()
  }

  private func sample() {
    guard let recorder else { return }
    recorder.updateMeters()
    // -45 dB and below reads as silence (room noise stays dots); the curve
    // keeps quiet sound low so speech stands out from it.
    let power = recorder.averagePower(forChannel: 0)
    let level = CGFloat(pow(max(0, min(1, (power + 45) / 45)), 1.6))
    elapsed = recorder.currentTime
    onSample?(level, elapsed)
    if let maxDuration, recorder.currentTime >= maxDuration { onLimit?() }
  }

  /// Stops and keeps the clip: its file and duration.
  func finish() -> (url: URL, duration: TimeInterval)? {
    guard let recorder else { return nil }
    let duration = isPaused ? elapsed : max(elapsed, recorder.currentTime)
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
    isPaused = false
    elapsed = 0
    deactivate()
  }

  private func deactivate() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

/// The composer's row while recording, as in Slack: cancel on the leading
/// edge, the live waveform, the elapsed time and a done button in the
/// accent colour where send sits.
///
/// With a clip style (`NativeComposerRecording`), an optional title line
/// above a 56 pt row: 40 pt cancel and done circles 8 pt from the edges,
/// 2 pt bars, the time and an optional pause/resume button.
@available(iOS 26.0, *)
final class RecordingBarView: UIView {
  var onCancel: (() -> Void)?
  var onDone: (() -> Void)?
  var onPause: (() -> Void)?
  var onResume: (() -> Void)?

  private let cancelButton = UIButton(configuration: .plain())
  private let doneButton = UIButton(configuration: .filled())
  private let pauseButton = UIButton(configuration: .plain())
  private let waveform = WaveformView()
  private let timeLabel = UILabel()
  private let titleIcon = UIImageView()
  private let titleLabel = UILabel()

  /// Centre of the edge buttons from the row's ends, and their size.
  var edgeCenter: CGFloat = 24
  var buttonSize: CGFloat = 32

  var accent: UIColor = .systemBlue {
    didSet {
      doneButton.configuration?.baseBackgroundColor = accent
      if clip == nil { waveform.barColor = accent }
    }
  }

  private enum Clip {
    static let titleTop: CGFloat = 8
    static let titleHeight: CGFloat = 18
    static let titleBottom: CGFloat = 4
    static let titleIconSize: CGFloat = 18
    static let titleGap: CGFloat = 4
    static let row: CGFloat = 56
    static let padding: CGFloat = 8
    static let button: CGFloat = 40
    static let spacing: CGFloat = 8
    static let pauseSpacing: CGFloat = 12
    static let waveHeight: CGFloat = 32
    static let iconSize: CGFloat = 24
    static let symbolSize: CGFloat = 17
    static let fontSize: CGFloat = 13
  }

  private var clip: [String: Any]?
  private var isPaused = false
  private var pauseLabel: String?
  private var resumeLabel: String?

  /// The bar's own height in the clip layout; nil for the default row,
  /// which takes the composer's.
  var preferredHeight: CGFloat? {
    guard let clip else { return nil }
    return (clip["title"] is String ? Clip.titleTop + Clip.titleHeight + Clip.titleBottom : 0) + Clip.row
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
    doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
    pauseButton.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if self.isPaused { self.onResume?() } else { self.onPause?() }
    }, for: .touchUpInside)

    timeLabel.textAlignment = .right
    titleIcon.contentMode = .center
    titleLabel.font = .systemFont(ofSize: Clip.fontSize)

    for v in [waveform, timeLabel, cancelButton, pauseButton, doneButton, titleIcon, titleLabel] as [UIView] { addSubview(v) }
    applyStyle()
    reset()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func setLabels(cancel: String?, done: String?) {
    cancelButton.accessibilityLabel = cancel
    doneButton.accessibilityLabel = done
  }

  /// The `recording` config: the clip layout, or nil for the default row.
  func setClip(_ raw: [String: Any]?) {
    clip = raw
    applyStyle()
    setNeedsLayout()
  }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    updatePauseButton()
  }

  func reset() {
    waveform.reset()
    setPaused(false)
    setElapsed(0)
  }

  func append(level: CGFloat, elapsed: TimeInterval) {
    waveform.append(level)
    setElapsed(elapsed)
  }

  private func setElapsed(_ elapsed: TimeInterval) {
    let seconds = Int(elapsed)
    timeLabel.text = String(format: clip == nil ? "%d:%02d" : "%02d:%02d", seconds / 60, seconds % 60)
  }

  private func applyStyle() {
    let clip = self.clip
    let iconColor = color(clip?["iconColor"]) ?? .label

    cancelButton.configuration?.image = clip == nil
      ? UIImage(systemName: "xmark")
      : icon(clip?["cancelIcon"], symbol: "xmark")
    cancelButton.configuration?.preferredSymbolConfigurationForImage = clip == nil
      ? .init(pointSize: 13, weight: .semibold)
      : nil
    cancelButton.configuration?.baseForegroundColor = iconColor
    cancelButton.configuration?.background.backgroundColor = clip == nil
      ? .tertiarySystemFill
      : color(clip?["cancelBackgroundColor"]) ?? .quaternarySystemFill
    cancelButton.configuration?.cornerStyle = .capsule
    cancelButton.configuration?.contentInsets = .zero

    doneButton.configuration?.image = clip == nil
      ? UIImage(systemName: "checkmark")
      : icon(clip?["doneIcon"], symbol: "checkmark")
    doneButton.configuration?.preferredSymbolConfigurationForImage = clip == nil
      ? .init(pointSize: 15, weight: .semibold)
      : nil
    doneButton.configuration?.baseForegroundColor = .white
    doneButton.configuration?.baseBackgroundColor = accent
    doneButton.configuration?.cornerStyle = .capsule
    doneButton.configuration?.contentInsets = .zero

    pauseButton.isHidden = !((clip?["pausable"] as? Bool) ?? false)
    pauseButton.configuration?.baseForegroundColor = iconColor
    pauseButton.configuration?.contentInsets = .zero
    pauseLabel = clip?["pauseLabel"] as? String
    resumeLabel = clip?["resumeLabel"] as? String
    updatePauseButton()

    timeLabel.font = .monospacedDigitSystemFont(ofSize: clip == nil ? 15 : Clip.fontSize, weight: clip == nil ? .medium : .regular)
    timeLabel.textColor = clip == nil ? .label : color(clip?["timeColor"]) ?? .secondaryLabel

    let title = clip?["title"] as? String
    titleLabel.text = title
    titleLabel.textColor = color(clip?["titleColor"]) ?? .secondaryLabel
    titleIcon.image = title == nil ? nil : icon(clip?["titleIcon"], symbol: "mic", size: Clip.titleIconSize, symbolSize: Clip.fontSize)
    titleIcon.tintColor = titleLabel.textColor
    titleLabel.isHidden = title == nil
    titleIcon.isHidden = title == nil

    waveform.style = clip == nil ? .levels : .clip
    waveform.barColor = clip == nil ? accent : color(clip?["waveColor"]) ?? .tertiaryLabel
  }

  private func updatePauseButton() {
    pauseButton.configuration?.image = isPaused
      ? icon(clip?["resumeIcon"], symbol: "mic")
      : icon(clip?["pauseIcon"], symbol: "pause")
    pauseButton.accessibilityLabel = isPaused ? resumeLabel : pauseLabel
  }

  private func color(_ raw: Any?) -> UIColor? {
    (raw as? NSNumber).map(UIColor.init(argb:))
  }

  private func icon(_ raw: Any?, symbol: String, size: CGFloat = Clip.iconSize, symbolSize: CGFloat = Clip.symbolSize) -> UIImage? {
    if let d = NativeIconDescriptor(raw) {
      return NativeIconRenderer.shared.image(for: d, pointSize: d.isSymbol ? symbolSize : size)?
        .withRenderingMode(.alwaysTemplate)
    }
    return UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if clip != nil {
      layoutClip()
      return
    }
    let w = bounds.width, h = bounds.height
    let s = buttonSize
    cancelButton.frame = CGRect(x: edgeCenter - s / 2, y: (h - s) / 2, width: s, height: s)
    doneButton.frame = CGRect(x: w - edgeCenter - s / 2, y: (h - s) / 2, width: s, height: s)
    let timeWidth = ceil(("0:00" as NSString).size(withAttributes: [.font: timeLabel.font!]).width) + 8
    timeLabel.frame = CGRect(x: doneButton.frame.minX - 12 - timeWidth, y: 0, width: timeWidth, height: h)
    let waveX = cancelButton.frame.maxX + 12
    waveform.frame = CGRect(x: waveX, y: (h - 24) / 2, width: max(0, timeLabel.frame.minX - 8 - waveX), height: 24)
  }

  private func layoutClip() {
    let w = bounds.width
    var top: CGFloat = 0
    if !titleLabel.isHidden {
      let labelWidth = min(ceil(titleLabel.intrinsicContentSize.width), w - 2 * Clip.padding - Clip.titleIconSize - Clip.titleGap)
      let total = Clip.titleIconSize + Clip.titleGap + labelWidth
      let x = (w - total) / 2
      titleIcon.frame = CGRect(x: x, y: Clip.titleTop, width: Clip.titleIconSize, height: Clip.titleHeight)
      titleLabel.frame = CGRect(x: x + Clip.titleIconSize + Clip.titleGap, y: Clip.titleTop, width: labelWidth, height: Clip.titleHeight)
      top = Clip.titleTop + Clip.titleHeight + Clip.titleBottom
    }
    let b = Clip.button, p = Clip.padding
    let buttonY = top + (Clip.row - b) / 2
    cancelButton.frame = CGRect(x: p, y: buttonY, width: b, height: b)
    doneButton.frame = CGRect(x: w - p - b, y: buttonY, width: b, height: b)
    pauseButton.frame = CGRect(x: doneButton.frame.minX - Clip.pauseSpacing - b, y: buttonY, width: b, height: b)
    let timeEnd = (pauseButton.isHidden ? doneButton.frame.minX : pauseButton.frame.minX) - Clip.spacing
    let timeWidth = ceil(("00:00" as NSString).size(withAttributes: [.font: timeLabel.font!]).width)
    timeLabel.frame = CGRect(x: timeEnd - timeWidth, y: top, width: timeWidth, height: Clip.row)
    let waveX = cancelButton.frame.maxX + Clip.spacing
    waveform.frame = CGRect(
      x: waveX,
      y: top + (Clip.row - Clip.waveHeight) / 2,
      width: max(0, timeLabel.frame.minX - Clip.spacing - waveX),
      height: Clip.waveHeight)
  }
}

/// Levels scrolling in from the trailing edge. `levels`: bars where there
/// was sound, dots where it was quiet and before the recording began.
/// `clip`: 2 pt rounded bars 1 pt apart, at least 2 pt tall, as in a sent
/// clip's waveform.
@available(iOS 26.0, *)
final class WaveformView: UIView {
  enum Style {
    case levels
    case clip

    var barWidth: CGFloat { self == .levels ? 3 : 2 }
    var step: CGFloat { self == .levels ? 5 : 3 }
  }

  var style: Style = .levels {
    didSet { if style != oldValue { setNeedsDisplay() } }
  }

  var barColor: UIColor = .systemBlue {
    didSet { setNeedsDisplay() }
  }

  private var levels: [CGFloat] = []
  private static let quiet: CGFloat = 0.08
  private static let clipMinHeight: CGFloat = 2

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
    let capacity = Int(bounds.width / style.step) + 1
    if levels.count > max(capacity, 1) * 2 { levels.removeFirst(levels.count - max(capacity, 1)) }
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    let barWidth = style.barWidth, step = style.step
    let isClip = style == .clip
    let slots = isClip ? Int((bounds.width + step - barWidth) / step) : Int(bounds.width / step)
    guard slots > 0 else { return }
    let midY = bounds.midY
    let dotColor = UIColor.tertiaryLabel
    let offset = isClip ? step - barWidth : (step - barWidth) / 2
    for slot in 0..<slots {
      let index = levels.count - slots + slot
      let x = bounds.width - CGFloat(slots - slot) * step + offset
      let level = index >= 0 ? levels[index] : 0
      if isClip {
        barColor.setFill()
        let height = max(Self.clipMinHeight, level * bounds.height)
        UIBezierPath(
          roundedRect: CGRect(x: x, y: midY - height / 2, width: barWidth, height: height),
          cornerRadius: barWidth / 2
        ).fill()
      } else if level < Self.quiet {
        dotColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: midY - barWidth / 2, width: barWidth, height: barWidth)).fill()
      } else {
        barColor.setFill()
        let height = max(barWidth, level * bounds.height)
        UIBezierPath(
          roundedRect: CGRect(x: x, y: midY - height / 2, width: barWidth, height: height),
          cornerRadius: barWidth / 2
        ).fill()
      }
    }
  }
}
