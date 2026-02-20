import UIKit
import ExampleUIKitScreens

@main
final class UIKitExampleAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let tab = UITabBarController()
        tab.viewControllers = UIKitDemoScreen.allCases.map { screen in
            let nav = UINavigationController(rootViewController: UIKitScreenFactory.make(screen))
            nav.tabBarItem = UITabBarItem(title: screen.rawValue.capitalized, image: nil, selectedImage: nil)
            return nav
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tab
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
