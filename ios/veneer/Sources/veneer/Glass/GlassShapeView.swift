import UIKit

/// One glass shape. Content (SF Symbol / label) is native so it gets the
/// system's vibrant treatment on glass — Flutter pixels can only ever sit
/// *under* this layer, never inside it.
@available(iOS 26.0, *)
final class GlassShapeView: UIVisualEffectView, UITextFieldDelegate {
  let id: Int
  var onTap: ((Int) -> Void)?
  var onMenu: ((Int, Int) -> Void)?
  var onSearch: ((Int, String, Any) -> Void)?
  var onSegment: ((Int, Int) -> Void)?
  private(set) var isInteractive = false
  private(set) var isShown = false
  /// Latest visibility requested by Flutter; `isShown` catches up async.
  var targetVisible = false

  /// Owning group and clip scope, as last placed by `GlassLayerView`.
  var groupId = 0
  var clipId = 0

  private var glass = UIGlassEffect(style: .regular)
  private let stack = UIStackView()
  private let imageView = UIImageView()
  private let label = UILabel()
  private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
  /// Covers the shape when it has a menu, so a tap opens the `UIMenu`
  /// growing out of the glass.
  private var menuButton: UIButton?
  /// Present when the shape is a search field: a real `UISearchTextField`
  /// with a clear background, so the shape's glass is its capsule.
  private var searchField: UISearchTextField?
  /// Present when the shape is a segment bar: equal-width buttons over a
  /// highlight capsule that slides to the selected one.
  private var segmentHost: UIView?
  private var segmentButtons: [UIButton] = []
  private let selectionView = UIView()
  private var segments: GlassSegmentsConfig?

  /// Default for glyphs and SVGs: matches an SF Symbol at the body text style.
  private static let iconSize: CGFloat = 22

  init(id: Int) {
    self.id = id
    super.init(effect: nil)
    cornerConfiguration = .capsule()

    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    imageView.preferredSymbolConfiguration = .init(textStyle: .body, scale: .medium)
    imageView.contentMode = .scaleAspectFit
    label.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
    label.adjustsFontForContentSizeCategory = true
    stack.addArrangedSubview(imageView)
    stack.addArrangedSubview(label)
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
    stack.alpha = 0
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func apply(_ c: GlassShapeConfig) {
    let g = UIGlassEffect(style: c.clear ? .clear : .regular)
    g.tintColor = c.tint
    g.isInteractive = c.interactive && c.search == nil && c.segments == nil
    glass = g
    if isShown { effect = g }

    let menu = NativeMenu.make(c.menu, id: "\(id)") { [weak self] item in
      guard let self, let index = Int(item.components(separatedBy: ".menu").last ?? "") else { return }
      self.onMenu?(self.id, index)
    }
    isInteractive = c.interactive || menu != nil || c.search != nil || c.segments != nil
    if c.interactive && menu == nil && c.search == nil && c.segments == nil {
      addGestureRecognizer(tap)
    } else {
      removeGestureRecognizer(tap)
    }
    applySearch(c.search)
    applySegments(c.segments)
    if let menu {
      let button = menuButton ?? {
        let b = UIButton(type: .custom)
        b.showsMenuAsPrimaryAction = true
        b.frame = contentView.bounds
        b.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(b)
        menuButton = b
        return b
      }()
      button.menu = menu
      button.accessibilityLabel = c.label
    } else {
      menuButton?.removeFromSuperview()
      menuButton = nil
    }

    if let r = c.cornerRadius {
      cornerConfiguration = .corners(radius: .fixed(r))
    } else {
      cornerConfiguration = .capsule()
    }

    // Symbols take the body text style via preferredSymbolConfiguration;
    // glyphs and SVGs render at the matching size as template images.
    imageView.preferredSymbolConfiguration =
      c.iconSize.map { UIImage.SymbolConfiguration(pointSize: $0) } ?? .init(textStyle: .body, scale: .medium)
    imageView.image = c.icon.flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? c.iconSize : c.iconSize ?? Self.iconSize)
    }
    imageView.isHidden = imageView.image == nil
    label.text = c.label
    label.isHidden = (c.label ?? "").isEmpty
    imageView.tintColor = c.foreground ?? .label
    label.textColor = c.foreground ?? .label
    accessibilityLabel = c.label
    isAccessibilityElement = c.interactive && menu == nil
    accessibilityTraits = c.interactive ? .button : .none
  }

  /// Materialize / dematerialize by animating `effect`, never `alpha`:
  /// a `UIVisualEffectView` with alpha < 1 renders incorrectly.
  func setVisible(_ visible: Bool) {
    guard visible != isShown else { return }
    isShown = visible
    if !visible { searchField?.resignFirstResponder() }
    UIView.animate(withDuration: visible ? 0.3 : 0.2) {
      self.effect = visible ? self.glass : nil
      self.stack.alpha = visible ? 1 : 0
      self.searchField?.alpha = visible ? 1 : 0
      self.segmentHost?.alpha = visible ? 1 : 0
    }
  }

  func dematerialize(completion: @escaping () -> Void) {
    isShown = false
    targetVisible = false
    searchField?.resignFirstResponder()
    UIView.animate(withDuration: 0.2, animations: {
      self.effect = nil
      self.stack.alpha = 0
      self.searchField?.alpha = 0
      self.segmentHost?.alpha = 0
    }, completion: { _ in completion() })
  }

  /// Hidden and non-interactive shapes must be transparent to hit testing,
  /// or they shadow interactive shapes beneath them (e.g. an offstage
  /// page's pill under an onstage button) and the touch falls to Flutter.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isInteractive, isShown else { return nil }
    return super.hitTest(point, with: event)
  }

  @objc private func handleTap() { onTap?(id) }

  // MARK: - Segments

  private static let defaultSelectionColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 1, alpha: 0.85)
  }

  private func applySegments(_ config: GlassSegmentsConfig?) {
    guard let config else {
      segmentHost?.removeFromSuperview()
      segmentHost = nil
      segmentButtons = []
      segments = nil
      return
    }
    stack.isHidden = true
    let previous = segments
    segments = config

    let host = segmentHost ?? {
      let view = UIView(frame: contentView.bounds)
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.alpha = isShown ? 1 : 0
      selectionView.isUserInteractionEnabled = false
      view.addSubview(selectionView)
      contentView.addSubview(view)
      segmentHost = view
      return view
    }()

    if previous?.signature != config.signature {
      segmentButtons.forEach { $0.removeFromSuperview() }
      segmentButtons = config.items.enumerated().map { index, item in
        let button = UIButton(type: .custom)
        if let icon = item.icon {
          let image = NativeIconRenderer.shared.image(
            for: icon,
            pointSize: config.iconSize
          )
          button.setImage(icon.isSymbol ? image : image?.withRenderingMode(.alwaysTemplate), for: .normal)
          button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: config.iconSize), forImageIn: .normal)
        } else {
          button.setTitle(item.label, for: .normal)
          button.titleLabel?.font = .systemFont(ofSize: config.iconSize)
        }
        button.accessibilityLabel = item.label
        button.addAction(UIAction { [weak self] _ in
          guard let self else { return }
          self.onSegment?(self.id, index)
        }, for: .touchUpInside)
        host.addSubview(button)
        return button
      }
    }

    selectionView.backgroundColor = config.selectionColor ?? Self.defaultSelectionColor
    for (index, button) in segmentButtons.enumerated() {
      let color = index == config.selected
        ? config.selectedForeground ?? .label
        : config.foreground ?? .secondaryLabel
      button.tintColor = color
      button.setTitleColor(color, for: .normal)
      button.accessibilityTraits = index == config.selected ? [.button, .selected] : .button
    }

    let selectionMoved = previous != nil && previous?.selected != config.selected
    if selectionMoved {
      UIView.animate(
        withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .allowUserInteraction]
      ) { self.layoutSegments() }
    } else {
      setNeedsLayout()
    }
  }

  private func layoutSegments() {
    guard let config = segments, let host = segmentHost, !segmentButtons.isEmpty else { return }
    let bounds = host.bounds
    let inset = config.padding
    let width = (bounds.width - inset * 2) / CGFloat(segmentButtons.count)
    let height = bounds.height - inset * 2
    for (index, button) in segmentButtons.enumerated() {
      button.frame = CGRect(x: inset + CGFloat(index) * width, y: inset, width: width, height: height)
    }
    let selected = config.selected
    selectionView.isHidden = !segmentButtons.indices.contains(selected)
    if segmentButtons.indices.contains(selected) {
      selectionView.frame = segmentButtons[selected].frame
      selectionView.layer.cornerRadius = height / 2
      selectionView.layer.cornerCurve = .continuous
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layoutSegments()
  }

  // MARK: - Search

  private func applySearch(_ config: GlassSearchConfig?) {
    guard let config else {
      searchField?.removeFromSuperview()
      searchField = nil
      stack.isHidden = false
      return
    }
    stack.isHidden = true
    let field = searchField ?? makeSearchField()
    field.placeholder = config.placeholder
    field.accessibilityLabel = config.placeholder
    if field.text != config.text { field.text = config.text }
  }

  private func makeSearchField() -> UISearchTextField {
    let field = UISearchTextField()
    field.translatesAutoresizingMaskIntoConstraints = false
    field.borderStyle = .none
    field.backgroundColor = .clear
    field.font = .preferredFont(forTextStyle: .body)
    field.adjustsFontForContentSizeCategory = true
    field.returnKeyType = .search
    field.clearButtonMode = .whileEditing
    field.autocorrectionType = .no
    field.delegate = self
    field.alpha = isShown ? 1 : 0
    field.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    field.addTarget(self, action: #selector(searchBegan), for: .editingDidBegin)
    field.addTarget(self, action: #selector(searchEnded), for: .editingDidEnd)
    contentView.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.searchInset),
      field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.searchInset),
      field.topAnchor.constraint(equalTo: contentView.topAnchor),
      field.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    searchField = field
    return field
  }

  /// Horizontal room between the glass capsule's edge and the field's
  /// magnifier / clear button.
  private static let searchInset: CGFloat = 8

  func searchCommand(_ command: String) {
    guard let field = searchField else { return }
    switch command {
    case "focus": field.becomeFirstResponder()
    case "blur": field.resignFirstResponder()
    case "clear":
      field.text = ""
      searchChanged()
    default: break
    }
  }

  @objc private func searchChanged() { onSearch?(id, "text", searchField?.text ?? "") }
  @objc private func searchBegan() { onSearch?(id, "focus", true) }
  @objc private func searchEnded() { onSearch?(id, "focus", false) }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    onSearch?(id, "submit", textField.text ?? "")
    textField.resignFirstResponder()
    return true
  }

  func textFieldShouldClear(_ textField: UITextField) -> Bool {
    DispatchQueue.main.async { [weak self] in self?.searchChanged() }
    return true
  }
}

private extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }
}
