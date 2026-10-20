import UIKit
import WebKit
import LocalAuthentication
import UserNotifications
import Security
import CryptoKit

private struct DeviceSettings: Codable {
    var lockEnabled = false
    var remindersEnabled = false
    var ownerId: String?
}

/// Native features are available only to the main first-party frame. No banking
/// popup receives this bridge, and no credentials or financial values are stored.
@MainActor
final class DeviceExperience: NSObject, WKScriptMessageHandlerWithReply, UNUserNotificationCenterDelegate {
    private weak var webView: WKWebView?
    private weak var hostView: UIView?
    private var settings = DeviceSettings()
    private var unlocked = true
    private var evaluating = false
    private var authentication: LAContext?
    private var lifecycle = DeviceUnlockLifecycle()
    private var cover: UIView!
    private var unlockButton: UIButton!
    private var coverMessage: UILabel!
    private var privacyVeil: UIVisualEffectView!
    private var scheduleError: String?
    private var scheduleTask: Task<Void, Never>?
    private var scheduleRevision = 0
    private var queuedPage: String?
    private let notifications = UNUserNotificationCenter.current()
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "mesames") + ".device",
         kSecAttrAccount as String: "preferences-v1"]
    }

    override init() {
        super.init()
        var query = keychainQuery; query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecSuccess, let data = value as? Data, let stored = try? JSONDecoder().decode(DeviceSettings.self, from: data) {
            settings = stored
        } else if result != errSecItemNotFound {
            // Corrupt or temporarily inaccessible protection settings fail closed.
            settings.lockEnabled = true
        }
        unlocked = !settings.lockEnabled
        notifications.delegate = self
    }
    private func save(_ next: DeviceSettings) throws {
        let data = try JSONEncoder().encode(next)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var result = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            result = SecItemAdd(keychainQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw NSError(domain: "MesAMesDevice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível salvar a proteção neste iPhone."]) }
        settings = next
    }
    func attach(to webView: WKWebView, in view: UIView) {
        self.webView = webView; hostView = view
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.84, green: 0.9, blue: 0.93, alpha: 1) : UIColor(red: 0.12, green: 0.23, blue: 0.28, alpha: 1) }
        cover = UIView(); cover.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.06, green: 0.09, blue: 0.11, alpha: 1) : UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1) }; cover.translatesAutoresizingMaskIntoConstraints = false
        cover.accessibilityViewIsModal = true
        let stack = UIStackView(); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        let mark = UIView(); mark.backgroundColor = UIColor(red: 0.14, green: 0.28, blue: 0.35, alpha: 1); mark.layer.cornerRadius = 24; mark.layer.cornerCurve = .continuous
        let image = UIImageView(image: UIImage(systemName: "chart.bar.fill")); image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = UIColor(red: 0.9, green: 0.76, blue: 0.35, alpha: 1)
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        mark.addSubview(image); NSLayoutConstraint.activate([mark.widthAnchor.constraint(equalToConstant: 88),mark.heightAnchor.constraint(equalToConstant: 88),image.centerXAnchor.constraint(equalTo: mark.centerXAnchor),image.centerYAnchor.constraint(equalTo: mark.centerYAnchor)])
        let title = UILabel(); title.text = "mês a mês"; title.textColor = ink; title.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 26, weight: .semibold)); title.adjustsFontForContentSizeCategory = true
        coverMessage = UILabel(); coverMessage.text = "Seu espaço, só seu."; coverMessage.font = .preferredFont(forTextStyle: .subheadline); coverMessage.adjustsFontForContentSizeCategory = true; coverMessage.textColor = .secondaryLabel; coverMessage.numberOfLines = 0; coverMessage.textAlignment = .center
        unlockButton = UIButton(type: .system); var configuration = UIButton.Configuration.plain()
        let context = LAContext(); _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        configuration.title = "Desbloquear"
        configuration.image = UIImage(systemName: context.biometryType == .faceID ? "faceid" : "lock.open"); configuration.imagePadding = 10; configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.baseForegroundColor = ink
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in var outgoing = incoming; outgoing.font = .preferredFont(forTextStyle: .subheadline); return outgoing }
        unlockButton.configuration = configuration; unlockButton.addAction(UIAction { [weak self] _ in self?.unlock() }, for: .touchUpInside)
        stack.addArrangedSubview(mark); stack.setCustomSpacing(24, after: mark); stack.addArrangedSubview(title)
        stack.addArrangedSubview(coverMessage); stack.addArrangedSubview(unlockButton)
        cover.addSubview(stack); view.addSubview(cover)
        privacyVeil = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial)); privacyVeil.translatesAutoresizingMaskIntoConstraints = false; privacyVeil.isHidden = true; privacyVeil.isUserInteractionEnabled = true
        view.addSubview(privacyVeil)
        NSLayoutConstraint.activate([privacyVeil.topAnchor.constraint(equalTo: view.topAnchor),privacyVeil.bottomAnchor.constraint(equalTo: view.bottomAnchor),privacyVeil.leadingAnchor.constraint(equalTo: view.leadingAnchor),privacyVeil.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        NSLayoutConstraint.activate([cover.topAnchor.constraint(equalTo: view.topAnchor),cover.bottomAnchor.constraint(equalTo: view.bottomAnchor),cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),stack.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 30),stack.trailingAnchor.constraint(lessThanOrEqualTo: cover.trailingAnchor, constant: -30)])
        cover.isHidden = unlocked
    }
    func enteredBackground() {
        lifecycle.enteredBackground(); unlocked = !settings.lockEnabled
        authentication?.invalidate(); conceal()
    }
    func willResignActive() {
        lifecycle.resignedActive()
        // Notification/Control Center and system prompts only make the scene
        // inactive. Preserve its unlocked session; show a neutral privacy veil.
        if unlocked {
            privacyVeil?.isHidden = false; webView?.accessibilityElementsHidden = true
            if let veil = privacyVeil { hostView?.bringSubviewToFront(veil) }
        } else { conceal() }
    }
    func activate() {
        lifecycle.becameActive()
        if settings.lockEnabled && !unlocked {
            conceal()
            // A cancelled/failed system prompt returning to the foreground is
            // not a new unlock request. Retrying stays under the user's control.
            if !evaluating && lifecycle.consumeAutomaticAttempt() { unlock() }
        } else { reveal() }
    }
    func conceal() {
        guard cover != nil else { return }
        privacyVeil?.isHidden = true
        unlockButton.isHidden = !lifecycle.active || !settings.lockEnabled || unlocked
        coverMessage.isHidden = !lifecycle.active
        unlockButton.isEnabled = !evaluating
        webView?.accessibilityElementsHidden = true
        cover.isHidden = false; hostView?.bringSubviewToFront(cover)
    }
    private func reveal() {
        guard lifecycle.canReveal(unlocked: unlocked) else { return }
        cover?.isHidden = true
        privacyVeil?.isHidden = true
        webView?.accessibilityElementsHidden = false
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('mesames-active'))", completionHandler: nil)
    }
    private func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        guard !evaluating else { completion(false); return }
        let context = LAContext(); context.localizedCancelTitle = "Cancelar"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { completion(false); return }
        evaluating = true; authentication = context; let epoch = lifecycle.epoch
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor in
                guard let self = self else { completion(false); return }
                self.evaluating = false; self.authentication = nil; completion(success && self.lifecycle.acceptsAuthentication(from: epoch))
            }
        }
    }
    private func unlock() {
        guard settings.lockEnabled, !unlocked, !evaluating, lifecycle.active else { return }
        authenticate(reason: "Desbloqueie seu espaço financeiro.") { [weak self] success in
            guard let self = self else { return }
            self.unlocked = success
            if success { self.coverMessage.text = "Seu espaço, só seu."; self.reveal() }
            else { self.coverMessage.text = "Tente novamente ou use o código do iPhone."; self.conceal() }
        }
    }
    private var ownerHash: String {
        SHA256.hash(data: Data((settings.ownerId ?? "").utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
    private func status() async -> [String: Any] {
        let authorization = await notifications.notificationSettings()
        let context = LAContext(); _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        let permission: String
        switch authorization.authorizationStatus {
        case .authorized: permission = "authorized"
        case .provisional, .ephemeral: permission = "provisional"
        case .denied: permission = "denied"
        default: permission = "notDetermined"
        }
        return ["version": "1.4.2", "lockEnabled": settings.lockEnabled, "unlocked": unlocked,
                "biometry": context.biometryType == .faceID ? "faceID" : context.biometryType == .touchID ? "touchID" : "passcode",
                "permission": permission, "remindersEnabled": settings.remindersEnabled,
                "reminderKinds": Array(DevicePolicy.destinations.keys), "scheduleError": scheduleError ?? "", "pendingPage": unlocked ? (queuedPage ?? "") : ""]
    }
    private func removeReminders() async {
        let pending = await notifications.pendingNotificationRequests()
        notifications.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("ma.") })
        let delivered = await notifications.deliveredNotifications()
        notifications.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix("ma.") })
        scheduleError = nil
    }
    private func updateReminders(_ jobs: [DeviceReminder], owner: String, revision: Int) async {
        guard revision == scheduleRevision, settings.ownerId == owner else { return }
        let authorization = await notifications.notificationSettings()
        guard settings.remindersEnabled, [.authorized, .provisional, .ephemeral].contains(authorization.authorizationStatus) else { await removeReminders(); return }
        let prefix = "ma.\(ownerHash)."
        scheduleError = nil
        let existing = await notifications.pendingNotificationRequests()
        let wanted = Set(jobs.map { prefix + $0.id })
        notifications.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("ma.") && !wanted.contains($0) })
        for job in jobs {
            guard revision == scheduleRevision, settings.ownerId == owner, settings.remindersEnabled else { return }
            let identifier = prefix + job.id
            if existing.contains(where: { $0.identifier == identifier && ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents == job.components }) { continue }
            let content = UNMutableNotificationContent(); content.title = job.title; content.body = job.body; content.sound = .default
            content.threadIdentifier = "mesames-reminders"
            content.userInfo = ["page": job.page, "ownerHash": ownerHash]
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: job.components, repeats: false))
            do { try await notifications.add(request) }
            catch { scheduleError = "Alguns lembretes não puderam ser programados. Abra o app novamente para tentar." }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard message.webView === webView, DevicePolicy.acceptsOrigin(scheme: origin.protocol, host: origin.host, port: origin.port, mainFrame: message.frameInfo.isMainFrame),
              let body = message.body as? [String: Any], let action = body["action"] as? String else { replyHandler(nil, "Origem não autorizada."); return }
        guard unlocked || ["clear", "status", "bind"].contains(action) else { replyHandler(nil, "Desbloqueie o aplicativo para continuar."); return }
        if action == "setLock" {
            guard let enabled = body["enabled"] as? Bool else { replyHandler(nil, "Preferência inválida."); return }
            authenticate(reason: enabled ? "Ative a proteção do Mês a mês." : "Confirme para desativar a proteção do Mês a mês.") { [weak self] success in
                guard let self = self else { replyHandler(nil, "Aplicativo indisponível."); return }
                guard success else { replyHandler(nil, "O desbloqueio não foi confirmado. A preferência anterior foi mantida."); return }
                do { var next = self.settings; next.lockEnabled = enabled; try self.save(next); self.unlocked = true; self.reveal()
                    Task { replyHandler(await self.status(), nil) }
                } catch { replyHandler(nil, error.localizedDescription) }
            }
            return
        }
        Task {
            do {
                switch action {
                case "status": break
                case "bind":
                    guard let owner = body["ownerId"] as? String, !owner.isEmpty, owner.count <= 200 else { replyHandler(nil, "Conta inválida."); return }
                    if settings.ownerId != owner {
                        scheduleRevision += 1; await scheduleTask?.value; await removeReminders(); queuedPage = nil
                        var next = settings; next.ownerId = owner; next.remindersEnabled = false; try save(next)
                    }
                case "clear":
                    scheduleRevision += 1; var next = settings; next.ownerId = nil; next.remindersEnabled = false; try save(next)
                    queuedPage = nil; await scheduleTask?.value; await removeReminders()
                case "setReminders":
                    guard let enabled = body["enabled"] as? Bool, settings.ownerId != nil else { replyHandler(nil, "Entre na sua conta para configurar lembretes."); return }
                    if enabled { _ = try await notifications.requestAuthorization(options: [.alert, .sound]) }
                    let permission = await notifications.notificationSettings().authorizationStatus
                    var next = settings; next.remindersEnabled = enabled && [.authorized, .provisional, .ephemeral].contains(permission); try save(next)
                    if !enabled { scheduleRevision += 1; await scheduleTask?.value; await removeReminders() }
                case "syncReminders":
                    guard let owner = body["ownerId"] as? String, settings.ownerId == owner else { replyHandler(nil, "Conta não autorizada."); return }
                    if body["enabled"] as? Bool == false { var next = settings; next.remindersEnabled = false; try save(next) }
                    scheduleRevision += 1; let revision = scheduleRevision
                    let jobs = DevicePolicy.reminders(body["jobs"]); let previous = scheduleTask
                    let task = Task { await previous?.value; await self.updateReminders(jobs, owner: owner, revision: revision) }
                    scheduleTask = task; await task.value
                case "ackNavigation": if body["page"] as? String == queuedPage { queuedPage = nil }
                case "openSettings":
                    if let url = URL(string: UIApplication.openSettingsURLString) { _ = await UIApplication.shared.open(url) }
                default: replyHandler(nil, "Ação não reconhecida."); return
                }
                replyHandler(await status(), nil)
            } catch { replyHandler(nil, error.localizedDescription) }
        }
    }
    func handleNotification(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        guard settings.ownerId != nil, info["ownerHash"] as? String == ownerHash,
              let page = info["page"] as? String, DevicePolicy.destinations.values.contains(page) else { return }
        queuedPage = page; if unlocked { reveal() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.handleNotification(response); completionHandler() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Avoid a redundant banner while the user is already inside the app.
        completionHandler([])
    }
}
