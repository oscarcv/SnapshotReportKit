import SwiftUI
import ExampleSwiftUIScreens

@main
struct SwiftUIExampleApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ForEach(SwiftUIDemoScreen.allCases, id: \.rawValue) { screen in
                    SwiftUIScreenFactory.make(screen)
                        .tabItem {
                            Text(screen.rawValue.capitalized)
                        }
                }
            }
        }
    }
}
