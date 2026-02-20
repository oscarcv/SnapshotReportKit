import UIKit

public enum UIKitDemoScreen: String, CaseIterable, Sendable {
    case login
    case dashboard
    case profile
    case catalog
    case cart
    case settings
}

public enum UIKitScreenFactory {
    public static func make(_ screen: UIKitDemoScreen) -> UIViewController {
        switch screen {
        case .login:
            return DemoCardViewController(
                titleText: "Login",
                subtitleText: "Secure sign-in and account recovery",
                accent: .systemBlue
            )
        case .dashboard:
            return DemoCardViewController(
                titleText: "Dashboard",
                subtitleText: "KPIs, conversion, and trend overview",
                accent: .systemGreen
            )
        case .profile:
            return DemoCardViewController(
                titleText: "Profile",
                subtitleText: "Identity, avatar, and subscription status",
                accent: .systemTeal
            )
        case .catalog:
            return DemoCardViewController(
                titleText: "Catalog",
                subtitleText: "Featured products and category filters",
                accent: .systemOrange
            )
        case .cart:
            return DemoCardViewController(
                titleText: "Cart",
                subtitleText: "Line items, totals, and payment action",
                accent: .systemRed
            )
        case .settings:
            return DemoCardViewController(
                titleText: "Settings",
                subtitleText: "Notifications, privacy, and support",
                accent: .systemPurple
            )
        }
    }
}

private final class DemoCardViewController: UIViewController {
    private let titleText: String
    private let subtitleText: String
    private let accent: UIColor

    init(titleText: String, subtitleText: String, accent: UIColor) {
        self.titleText = titleText
        self.subtitleText = subtitleText
        self.accent = accent
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.textColor = accent
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitleText
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.configuration?.title = "Primary Action"
        button.tintColor = accent

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, button])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 20
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])
    }
}
