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
    private var authenticationEpoch = 0
    private var cover: UIView!
    private var unlockButton: UIButton!
    private var coverMessage: UILabel!
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
        cover = UIView(); cover.backgroundColor = .systemBackground; cover.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImageView(image: UIImage(systemName: "lock.shield")); image.tintColor = UIColor(red: 0.14, green: 0.28, blue: 0.35, alpha: 1)
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        let title = UILabel(); title.text = "Mês a mês"; title.font = .preferredFont(forTextStyle: .title1); title.adjustsFontForContentSizeCategory = true
        coverMessage = UILabel(); coverMessage.text = "Seu espaço financeiro está protegido."; coverMessage.font = .preferredFont(forTextStyle: .body); coverMessage.textColor = .secondaryLabel; coverMessage.numberOfLines = 0; coverMessage.textAlignment = .center
        unlockButton = UIButton(type: .system); var configuration = UIButton.Configuration.filled()
        configuration.title = "Desbloquear"; configuration.cornerStyle = .large
        configuration.baseBackgroundColor = UIColor(red: 0.14, green: 0.28, blue: 0.35, alpha: 1)
        unlockButton.configuration = configuration; unlockButton.addAction(UIAction { [weak self] _ in self?.unlock() }, for: .touchUpInside)
        stack.addArrangedSubview(image); stack.addArrangedSubview(title)
        stack.addArrangedSubview(coverMessage); stack.addArrangedSubview(unlockButton)
        cover.addSubview(stack); view.addSubview(cover)
        NSLayoutConstraint.activate([cover.topAnchor.constraint(equalTo: view.topAnchor),cover.bottomAnchor.constraint(equalTo: view.bottomAnchor),cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),stack.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 30),stack.trailingAnchor.constraint(lessThanOrEqualTo: cover.trailingAnchor, constant: -30)])
        cover.isHidden = unlocked
    }
    func enteredBackground() {
        authenticationEpoch += 1; unlocked = !settings.lockEnabled
        authentication?.invalidate(); conceal()
    }
    func activate() {
        guard UIApplication.shared.applicationState == .active else { return }
        if settings.lockEnabled && !unlocked { conceal(); unlock() } else { reveal() }
    }
    func conceal() {
        guard cover != nil else { return }
        unlockButton.isHidden = !settings.lockEnabled || unlocked
        cover.isHidden = false; hostView?.bringSubviewToFront(cover)
    }
    private func reveal() {
        guard UIApplication.shared.applicationState == .active, unlocked else { return }
        cover?.isHidden = true
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('mesames-active'))", completionHandler: nil)
    }
    private func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        guard !evaluating else { completion(false); return }
        let context = LAContext(); context.localizedCancelTitle = "Cancelar"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { completion(false); return }
        evaluating = true; authentication = context; let epoch = authenticationEpoch
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor in
                guard let self = self else { completion(false); return }
                self.evaluating = false; self.authentication = nil; completion(success && epoch == self.authenticationEpoch)
            }
        }
    }
    private func unlock() {
        guard settings.lockEnabled, !unlocked, !evaluating else { return }
        authenticate(reason: "Desbloqueie seu espaço financeiro.") { [weak self] success in
            guard let self = self else { return }
            self.unlocked = success
            if success { self.coverMessage.text = "Seu espaço financeiro está protegido."; self.reveal() }
            else { self.coverMessage.text = "Toque em Desbloquear para tentar novamente. Você também pode usar o código do iPhone."; self.conceal() }
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
        return ["version": "1.4.0", "lockEnabled": settings.lockEnabled, "unlocked": unlocked,
                "biometry": context.biometryType == .faceID ? "faceID" : context.biometryType == .touchID ? "touchID" : "passcode",
                "permission": permission, "remindersEnabled": settings.remindersEnabled,
                "pendingPage": unlocked ? (queuedPage ?? "") : ""]
    }
    private func removeReminders() async {
        let pending = await notifications.pendingNotificationRequests()
        notifications.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("ma.") })
        let delivered = await notifications.deliveredNotifications()
        notifications.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix("ma.") })
    }
    private func updateReminders(_ jobs: [DeviceReminder], owner: String, revision: Int) async {
        guard revision == scheduleRevision, settings.ownerId == owner else { return }
        let authorization = await notifications.notificationSettings()
        guard settings.remindersEnabled, [.authorized, .provisional, .ephemeral].contains(authorization.authorizationStatus) else { await removeReminders(); return }
        let prefix = "ma.\(ownerHash)."
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
            try? await notifications.add(request)
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
                    var next = settings; next.remindersEnabled = enabled; try save(next)
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
              let page = info["page"] as? String, ["Cartões", "Movimentações", "Metas"].contains(page) else { return }
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
