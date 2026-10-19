import UIKit
import UserNotifications

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = FinanceViewController()
        window.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.063, green: 0.086, blue: 0.106, alpha: 1)
                : UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1)
        }
        window.makeKeyAndVisible()
        self.window = window
        if let response = connectionOptions.notificationResponse {
            (window.rootViewController as? FinanceViewController)?.openNotification(response)
        }
    }
    // Synchronous callbacks cover the web content before iOS takes its snapshot.
    func sceneWillResignActive(_ scene: UIScene) { (window?.rootViewController as? FinanceViewController)?.concealPrivateContent() }
    func sceneDidEnterBackground(_ scene: UIScene) { (window?.rootViewController as? FinanceViewController)?.enteredBackground() }
    func sceneDidBecomeActive(_ scene: UIScene) { (window?.rootViewController as? FinanceViewController)?.becameActive() }
}
