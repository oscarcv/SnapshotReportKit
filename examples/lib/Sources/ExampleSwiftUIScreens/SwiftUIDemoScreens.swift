import SwiftUI

public enum SwiftUIDemoScreen: String, CaseIterable, Sendable {
    case onboarding
    case feed
    case detail
    case messages
    case checkout
    case account
}

public enum SwiftUIScreenFactory {
    @MainActor
    public static func make(_ screen: SwiftUIDemoScreen) -> AnyView {
        switch screen {
        case .onboarding:
            return AnyView(DemoScreen(title: "Onboarding", subtitle: "Welcome flow and feature highlights", tint: .cyan))
        case .feed:
            return AnyView(DemoScreen(title: "Feed", subtitle: "Editorial cards and dynamic recommendations", tint: .mint))
        case .detail:
            return AnyView(DemoScreen(title: "Detail", subtitle: "Long-form content and related items", tint: .blue))
        case .messages:
            return AnyView(DemoScreen(title: "Messages", subtitle: "Conversations and unread indicators", tint: .indigo))
        case .checkout:
            return AnyView(DemoScreen(title: "Checkout", subtitle: "Address, shipping, and confirmation", tint: .orange))
        case .account:
            return AnyView(DemoScreen(title: "Account", subtitle: "Security, billing, and preferences", tint: .pink))
        }
    }
}

private struct DemoScreen: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("Primary Action") {}
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(20)
        }
    }
}
