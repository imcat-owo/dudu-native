//
//  D20a (2026-10-08): at-most-one proactive local notification.
//
//  Rules (from the manuals):
//  - When she is away, at most ONE notification is scheduled. It fires hours
//    later, only if she has not come back.
//  - When she returns (foreground), every pending proactive notification is
//    cancelled — no stale pings.
//  - Copy is template-based: iOS cannot wake the AI to compose while
//    suspended. Tone is "我想起你", never "系统通知你". Zero emoji.
//  - Utilize iOS rules, don't fight them: this uses the existing
//    NotificationCategoryRegistry union (ScheduledPromptManager) so we never
//    unregister another feature's categories.
//  - Permission comes from her: Dudu/Views/Permissions/ owns the ask. This
//    scheduler only checks the granted state and stays silent without it.

import Foundation
import UserNotifications

@MainActor
final class ProactiveNotificationScheduler {
    static let shared = ProactiveNotificationScheduler()

    private static let categoryId = "proactive"
    private static let idPrefix = "proactive-"

    private let logger = AppLogger(category: "ProactiveNotify")
    private init() {}

    /// Register the proactive category through the union registry.
    /// Safe to call repeatedly; never stomps other features' categories.
    func registerCategory() {
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [],
            intentIdentifiers: []
        )
        NotificationCategoryRegistry.register(category)
    }

    /// Schedule one proactive notification, replacing any previously
    /// scheduled one. Honest ceiling: one at a time, always.
    func scheduleAtMostOne(
        id: String,
        title: String,
        body: String,
        afterSeconds: TimeInterval,
        userInfo: [String: Any] = [:]
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            // Not determined / denied: stay silent. She enables it through
            // the existing Permissions flow; we never ambush-ask from here.
            logger.info("[notify] permission not granted (\(settings.authorizationStatus.rawValue)) — staying silent")
            return
        }
        // One at a time: clear any older proactive requests first.
        let pending: [UNNotificationRequest] = await withCheckedContinuation { cont in
            center.getPendingNotificationRequests { cont.resume(returning: $0) }
        }
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        var info = userInfo
        info["proactive"] = true
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, afterSeconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.idPrefix + id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            logger.info("[notify] scheduled \(id) in \(Int(afterSeconds))s")
        } catch {
            logger.warning("[notify] schedule failed: \(error.localizedDescription)")
        }
    }

    /// Cancel every pending AND delivered proactive notification.
    /// Called on foreground — a returning her must never see a stale ping.
    func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }
}
