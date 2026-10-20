import Foundation

// Scene callbacks are authoritative for this window. The app-wide state can
// still be inactive inside sceneDidBecomeActive, especially around Face ID.
struct DeviceUnlockLifecycle {
    private(set) var active = false
    private(set) var epoch = 0
    private var automaticAttemptAvailable = true
    mutating func becameActive() { active = true }
    mutating func resignedActive() { active = false }
    mutating func enteredBackground() {
        active = false; epoch += 1; automaticAttemptAvailable = true
    }
    mutating func consumeAutomaticAttempt() -> Bool {
        guard active && automaticAttemptAvailable else { return false }
        automaticAttemptAvailable = false; return true
    }
    func canReveal(unlocked: Bool) -> Bool { active && unlocked }
    func acceptsAuthentication(from attemptEpoch: Int) -> Bool { epoch == attemptEpoch }
}

enum DevicePolicy {
    static let destinations = ["bills": "Cartões", "payments": "Movimentações", "goals": "Metas", "income": "Movimentações", "closing": "Cartões", "weekly": "Relatórios", "planning": "Planejamento"]
    static let host = "mes-a-mes-financas.rosycream3.chatgpt.site"
    static func acceptsOrigin(scheme: String, host: String, port: Int, mainFrame: Bool) -> Bool {
        mainFrame && scheme == "https" && host.lowercased() == self.host && (port == 0 || port == 443)
    }
    static func reminders(_ values: Any?, now: Date = Date(), calendar: Calendar = .current) -> [DeviceReminder] {
        guard let rows = values as? [[String: Any]] else { return [] }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 46, to: start)!
        var seen = Set<String>()
        return rows.prefix(60).compactMap { row in
            guard let id = row["id"] as? String, let kind = row["kind"] as? String,
                  let date = row["date"] as? String, let hour = row["hour"] as? Int,
                  let page = row["page"] as? String,
                  destinations[kind] == page,
                  (7...21).contains(hour), id == "ma-\(kind)-\(date)", !seen.contains(id) else { return nil }
            let parts = date.split(separator: "-").compactMap { Int($0) }
            guard date.count == 10, parts.count == 3 else { return nil }
            var components = DateComponents()
            components.calendar = calendar; components.timeZone = calendar.timeZone
            components.year = parts[0]; components.month = parts[1]; components.day = parts[2]; components.hour = hour
            guard let fire = calendar.date(from: components), fire > now, fire < end,
                  calendar.component(.year, from: fire) == parts[0],
                  calendar.component(.month, from: fire) == parts[1],
                  calendar.component(.day, from: fire) == parts[2] else { return nil }
            seen.insert(id)
            return DeviceReminder(id: id, kind: kind, page: page, components: components)
        }.sorted { $0.components.date! < $1.components.date! }
    }
}
struct DeviceReminder {
    let id: String
    let kind: String
    let page: String
    let components: DateComponents
    var title: String { ["bills": "Fatura a vencer", "payments": "Pagamento previsto", "goals": "Sua meta está chegando", "income": "Receita prevista", "closing": "Fechamento do cartão", "weekly": "Seu momento da semana", "planning": "Um novo mês pela frente"][kind]! }
    var body: String { ["bills": "Confira suas próximas faturas no Mês a mês.", "payments": "Confira os pagamentos previstos no Mês a mês.", "goals": "Confira o prazo e o progresso das suas metas no Mês a mês.", "income": "Confira as entradas previstas no Mês a mês.", "closing": "Confira os próximos fechamentos no Mês a mês.", "weekly": "Reserve um momento para revisar seu mês.", "planning": "Que tal preparar o planejamento do próximo mês?"][kind]! }
}
