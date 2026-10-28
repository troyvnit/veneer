import UIKit

/// The list a prompt composer shows right above itself, e.g. people to
/// mention: glass, radius 24, 6 pt above and below 52 pt rows — a 32 pt round
/// image 16 pt from the edge, the title and subtitle 12 pt after it, the
/// detail 16 pt from the trailing edge. Scrolls past five and a half rows.
///
/// `{items: [{id, title, subtitle?, detail?, image?}], titleStyle?, subtitleStyle?, detailStyle?}`
@available(iOS 26.0, *)
final class ComposerSuggestionsView: UIView, UITableViewDataSource, UITableViewDelegate {
  static let gap: CGFloat = 8
  static let rowHeight: CGFloat = 52
  static let padding: CGFloat = 6
  static let visibleRows: CGFloat = 5.5
  static let cornerRadius: CGFloat = 24

  var onSelect: ((String) -> Void)?

  private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
  private let table = UITableView(frame: .zero, style: .plain)
  private var items: [[String: Any]] = []
  private var styles: [String: Any] = [:]
  private var lastSpec: NSDictionary?

  var hasItems: Bool { !items.isEmpty }

  /// Every row's height, capped at five and a half rows.
  var preferredHeight: CGFloat {
    guard hasItems else { return 0 }
    return min(CGFloat(items.count), Self.visibleRows) * Self.rowHeight + 2 * Self.padding
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    glass.cornerConfiguration = .corners(radius: .fixed(Self.cornerRadius))
    glass.clipsToBounds = true
    addSubview(glass)

    table.backgroundColor = .clear
    table.separatorStyle = .none
    table.rowHeight = Self.rowHeight
    table.contentInset = UIEdgeInsets(top: Self.padding, left: 0, bottom: Self.padding, right: 0)
    table.showsVerticalScrollIndicator = true
    table.keyboardDismissMode = .none
    table.dataSource = self
    table.delegate = self
    table.register(SuggestionCell.self, forCellReuseIdentifier: SuggestionCell.reuseId)
    glass.contentView.addSubview(table)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Returns whether anything changed.
  @discardableResult
  func configure(_ spec: [String: Any]?) -> Bool {
    let dictionary = spec.map { $0 as NSDictionary }
    guard dictionary != lastSpec else { return false }
    lastSpec = dictionary
    items = (spec?["items"] as? [[String: Any]]) ?? []
    styles = spec ?? [:]
    table.reloadData()
    if hasItems { table.setContentOffset(CGPoint(x: 0, y: -Self.padding), animated: false) }
    return true
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    glass.frame = bounds
    table.frame = glass.contentView.bounds
    table.isScrollEnabled = CGFloat(items.count) > Self.visibleRows
  }

  // MARK: - UITableViewDataSource

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: SuggestionCell.reuseId, for: indexPath)
    (cell as? SuggestionCell)?.configure(items[indexPath.row], styles: styles)
    return cell
  }

  // MARK: - UITableViewDelegate

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard let id = items[indexPath.row]["id"] as? String else { return }
    onSelect?(id)
  }
}

/// `[(●) Title            Detail]` / `[    Subtitle              ]`
@available(iOS 26.0, *)
private final class SuggestionCell: UITableViewCell {
  static let reuseId = "suggestion"

  private static let inset: CGFloat = 16
  private static let imageSize: CGFloat = 32
  private static let imageGap: CGFloat = 12
  private static let detailGap: CGFloat = 8
  private static let titleHeight: CGFloat = 22
  private static let subtitleHeight: CGFloat = 18
  private static let highlightInset: CGFloat = 6
  private static let highlightRadius: CGFloat = 18

  private let avatar = UIImageView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let detailLabel = UILabel()
  private let highlight = UIView()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear
    selectionStyle = .none
    highlight.backgroundColor = .systemFill
    highlight.layer.cornerRadius = Self.highlightRadius
    highlight.layer.cornerCurve = .continuous
    highlight.alpha = 0
    avatar.contentMode = .scaleAspectFill
    avatar.clipsToBounds = true
    avatar.layer.cornerRadius = Self.imageSize / 2
    avatar.backgroundColor = .tertiarySystemFill
    for label in [titleLabel, subtitleLabel, detailLabel] {
      label.numberOfLines = 1
      label.lineBreakMode = .byTruncatingTail
      label.adjustsFontForContentSizeCategory = false
    }
    detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    for v in [highlight, avatar, titleLabel, subtitleLabel, detailLabel] as [UIView] { contentView.addSubview(v) }
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ item: [String: Any], styles: [String: Any]) {
    let title = item["title"] as? String ?? ""
    let subtitle = item["subtitle"] as? String ?? ""
    let detail = item["detail"] as? String ?? ""
    titleLabel.attributedText = ReplyBannerView.text(
      title, style: styles["titleStyle"], size: 17, weight: 400, color: .label)
    subtitleLabel.attributedText = ReplyBannerView.text(
      subtitle, style: styles["subtitleStyle"], size: 13, weight: 400, color: .secondaryLabel)
    detailLabel.attributedText = ReplyBannerView.text(
      detail, style: styles["detailStyle"], size: 13, weight: 400, color: .secondaryLabel)
    subtitleLabel.isHidden = subtitle.isEmpty
    detailLabel.isHidden = detail.isEmpty
    avatar.image = NativeIconDescriptor(item["image"]).flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: Self.imageSize)
    }
    accessibilityLabel = [title, subtitle, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    setNeedsLayout()
  }

  override func setHighlighted(_ highlighted: Bool, animated: Bool) {
    super.setHighlighted(highlighted, animated: animated)
    UIView.animate(withDuration: animated ? 0.15 : 0) { self.highlight.alpha = highlighted ? 1 : 0 }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let b = contentView.bounds
    highlight.frame = b.insetBy(dx: Self.highlightInset, dy: 0)
    avatar.frame = CGRect(x: Self.inset, y: (b.height - Self.imageSize) / 2, width: Self.imageSize, height: Self.imageSize)
    let textX = avatar.frame.maxX + Self.imageGap
    var trailing = b.width - Self.inset
    if !detailLabel.isHidden {
      let width = ceil(detailLabel.intrinsicContentSize.width)
      detailLabel.frame = CGRect(x: trailing - width, y: 0, width: width, height: b.height)
      trailing -= width + Self.detailGap
    }
    let textW = max(0, trailing - textX)
    if subtitleLabel.isHidden {
      titleLabel.frame = CGRect(x: textX, y: 0, width: textW, height: b.height)
    } else {
      let top = (b.height - Self.titleHeight - Self.subtitleHeight) / 2
      titleLabel.frame = CGRect(x: textX, y: top, width: textW, height: Self.titleHeight)
      subtitleLabel.frame = CGRect(x: textX, y: top + Self.titleHeight, width: textW, height: Self.subtitleHeight)
    }
  }
}
