#if os(iOS)
import UIKit

/// What shows in place of a page that couldn't be fetched, with a button
/// to fetch it again, so a slow or failing site never leaves a page
/// spinning forever.
final class PageFailureView: UIView {
    var retry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let symbol = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        symbol.tintColor = .secondaryLabel
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        let label = UILabel()
        label.text = String(localized: "This page couldn't load.", bundle: .module)
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        var configuration = UIButton.Configuration.gray()
        configuration.title = String(localized: "Try Again", bundle: .module)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.retry?()
        })
        let stack = UIStackView(arrangedSubviews: [symbol, label, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
        // The page is dark whatever the system's appearance.
        overrideUserInterfaceStyle = .dark
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#endif
