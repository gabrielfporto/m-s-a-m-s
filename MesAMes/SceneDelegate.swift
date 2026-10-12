import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = FinanceViewController()
        window.backgroundColor = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        window.makeKeyAndVisible()
        self.window = window
    }
}
