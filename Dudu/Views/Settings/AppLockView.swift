import SwiftUI

// MARK: - AppLockView · 应用锁
//
// D11. Settings UI for the app-level lock in SessionLockStore
// (appLockEnabled / appLockIdleSeconds / appIsLocked), gated by the real
// BiometricAuth capability probe.
//
// Behavior (matches the old Dudu H8 spec):
// - Enabling requires one successful biometric/passcode verification first.
// - On relaunch / foreground return, the gate re-evaluates and shows the
//   lock overlay when the idle window has elapsed (or always, for lock-on-exit).
// - When the device has no usable biometrics or passcode, the toggle is
//   honestly disabled with the reason stated — no fake "enabled" state.

struct AppLockView: View {
    @ObservedObject private var store = SessionLockStore.shared

    @State private var verifying = false
    @State private var enableError: String?

    /// Idle choices for the APP lock. Values are the engine's contract
    /// (SessionLockStore.appLockIdleSeconds): -1 = lock on background,
    /// 0 = never auto re-lock. Labels are presentation only.
    private static let idleChoices: [(seconds: Int, label: String)] = [
        (-1, "切到后台时"),
        (30, "30 秒"),
        (60, "1 分钟"),
        (300, "5 分钟"),
        (600, "10 分钟"),
        (900, "15 分钟"),
        (3600, "1 小时"),
        (0, "从不自动锁定"),
    ]

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { store.appLockEnabled },
                    set: { setEnabled($0) }
                )) {
                    HStack(spacing: 12) {
                        DuduIcon(systemName: BiometricAuth.biometryIconName)
                            .font(DuduTheme.appFont(size: 15))
                            .foregroundStyle(DuduTheme.pink)
                            .frame(width: 30, height: 30)
                            .background(DuduTheme.duduIconChip)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("应用锁")
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                            Text(lockSubtitle)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                }
                .tint(DuduTheme.pink)
                .disabled(verifying || !BiometricAuth.isAvailable)

                if verifying {
                    HStack {
                        ProgressView()
                            .tint(DuduTheme.pink)
                        Text("正在验证…")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                // [P3] Tri-state: before the probe resolves we know nothing —
                // show neither the toggle's honest-disable nor a fake "不可用".
                if BiometricAuth.isProbeResolved && !BiometricAuth.isAvailable {
                    // Honest fallback: never pretend the lock is protecting
                    // anything when there is nothing to verify against.
                    HStack(spacing: 8) {
                        DuduIcon(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(DuduTheme.pink)
                        Text("这台设备当前无法使用生物识别或锁屏密码（可能尚未录入/设置），应用锁暂不能启用。")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                if let enableError {
                    Text(enableError)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.pink)
                }
            } footer: {
                DuduSectionFooter {
                    Text("生物识别只在系统安全区内比对，嘟嘟只收到成功或失败的结果——你的面容与指纹从不离开本机。")
                }
            }

            if store.appLockEnabled {
                Section {
                    Picker("闲置后锁定", selection: Binding(
                        get: { store.appLockIdleSeconds },
                        set: { store.appLockIdleSeconds = $0 }
                    )) {
                        ForEach(Self.idleChoices, id: \.seconds) { choice in
                            Text(choice.label).tag(choice.seconds)
                        }
                    }
                } header: {
                    DuduSectionTitle("再次锁定")
                }

                Section {
                    Button("立即锁定") {
                        // [P2] Force the lock now — idle == 0 ("never")
                        // only governs automatic re-locking.
                        store.lockAppNow()
                    }
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.pink)
                } footer: {
                    DuduSectionFooter {
                        Text("点按后嘟嘟立即锁定，需要重新验证才能进入。")
                    }
                }
            }
        }
        .duduCardList()
        .navigationTitle("应用锁")
    }

    private var lockSubtitle: String {
        // [P3] Only claim "不可用" once the probe has actually resolved.
        if BiometricAuth.isProbeResolved && !BiometricAuth.isAvailable { return "不可用" }
        guard store.appLockEnabled else {
            return "用\(BiometricAuth.biometryDisplayName)确认是你，才能进嘟嘟"
        }
        return "已开启 · \(BiometricAuth.biometryDisplayName)"
    }

    /// Enabling is a deliberate act: one successful verification first, so a
    /// borrowed-unlocked phone can't be locked against its owner silently.
    private func setEnabled(_ on: Bool) {
        enableError = nil
        if on {
            guard BiometricAuth.isAvailable else {
                enableError = "这台设备没有可用的验证方式，无法启用。"
                return
            }
            verifying = true
            Task {
                let ok = await BiometricAuth.authenticate(
                    reason: "验证一次，之后用\(BiometricAuth.biometryDisplayName)解锁嘟嘟")
                if ok {
                    // Just verified — record the unlock so the gate doesn't
                    // immediately challenge what the user just proved.
                    store.appLockEnabled = true
                    store.noteAppUnlock()
                } else {
                    enableError = "验证未通过，应用锁未启用。"
                }
                verifying = false
            }
        } else {
            store.appLockEnabled = false
            store.clearAppUnlock()
            store.evaluateAppLock()
        }
    }
}

// MARK: - AppLockOverlayView · 锁定遮罩

/// Full-screen lock screen shown when `appIsLocked`. Covers the whole app
/// (it is applied at the TabView root) — chat, settings, everything.
struct AppLockOverlayView: View {
    @ObservedObject private var store = SessionLockStore.shared
    @State private var busy = false
    @State private var failedMessage: String?

    var body: some View {
        ZStack {
            DuduTheme.duduBackground
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer()
                DuduIcon(systemName: BiometricAuth.biometryIconName)
                    .font(DuduTheme.appFont(size: 52, weight: .regular))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(width: 96, height: 96)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                Text("嘟嘟已锁定")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Text("用\(BiometricAuth.biometryDisplayName)验证后进入。")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                if busy {
                    ProgressView()
                        .tint(DuduTheme.pink)
                        .padding(.top, 8)
                } else {
                    Button {
                        unlock()
                    } label: {
                        Text("解锁")
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.brandBrown)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 12)
                            .background(DuduTheme.pink)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
                if let failedMessage {
                    Text(failedMessage)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Spacer()
                // Honest microcopy: what the lock does and doesn't do.
                Text("生物识别在系统安全区内完成，嘟嘟只知道成功或失败。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() {
        failedMessage = nil
        busy = true
        Task {
            // .deviceOwnerAuthentication chains biometrics → system passcode
            // fallback natively (see BiometricAuth.authenticate).
            let ok = await BiometricAuth.authenticate(reason: "解锁嘟嘟")
            if ok {
                store.noteAppUnlock()
            } else {
                failedMessage = "验证未通过，再试一次吧。"
            }
            busy = false
        }
    }
}

// MARK: - AppLockGate · 应用级锁定门

/// ViewModifier applied once at the app root (DuduTabView). Owns:
/// - the lock overlay (above everything, including the tab bar),
/// - the privacy screen shown while the app sits in the switcher,
/// - foreground/background evaluation via SessionLockStore,
/// - the one-time off-main-thread biometric capability prewarm.
///
/// Kept as a modifier (not edits scattered through DuduTabView) so the
/// root diff stays one line.
struct AppLockGate: ViewModifier {
    @ObservedObject private var store = SessionLockStore.shared
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .overlay {
                if store.appLockEnabled && store.appIsLocked {
                    AppLockOverlayView()
                } else if store.showPrivacyScreen {
                    // Task-switcher cover: plain background, no content peek.
                    DuduTheme.duduBackground
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                // [P0] prewarm is an async ~552 ms XPC probe. The onAppear
                // evaluate above intentionally HOLDS the locked state while
                // the probe is in flight (see evaluateAppLock), so settle
                // the real state with one more evaluate once the probe
                // lands. This never blocks the UI — no startup white-screen:
                // the initial state is locked (the overlay), and only a
                // successful auth clears it.
                BiometricAuth.prewarm()
                await BiometricAuth.awaitPrewarm()
                store.evaluateAppLock()
            }
            .onAppear {
                // Cold launch: appIsLocked already starts true when the lock
                // is enabled (SessionLockStore init). While the capability
                // probe is unresolved this evaluate holds that state instead
                // of clearing it; the .task above settles it post-prewarm.
                store.evaluateAppLock()
            }
            .onChange(of: phase) { _, newPhase in
                switch newPhase {
                case .background:
                    // Record WHEN we left so evaluateAppLock can apply the
                    // lock-on-exit grace window (no repeated Face ID for
                    // banner/control-center blips). showPrivacyScreen covers
                    // the switcher until foreground clears it.
                    store.noteAppBackgrounded()
                    store.showPrivacyScreen = true
                case .active:
                    // Clears showPrivacyScreen and re-locks when due.
                    store.evaluateAppLock()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
    }
}
