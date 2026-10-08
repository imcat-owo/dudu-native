import SafariServices
import SwiftUI
import UIKit

// MARK: - D25 · SandboxSettingsView
//
// The sandbox settings page: dual-mode backend switcher (req 2), cloud
// server list with add/edit/delete/test-connection (req 1), and the
// URL-scheme "open in other app" list (req 3).
//
// User-visible behavior matches the old Dudu sandbox sheet
// (openmuse/apps/mobile/src/sandbox/sandbox-ui.tsx):
// - Backend cards with radio select + live status dot + detail line.
// - Server rows: tap = switch to it and connect; pencil = edit; trash =
//   delete (with confirm). "+" adds. The edit form validates, lets her keep
//   the saved secret by leaving the field blank, and has a real "test
//   connection" button that probes the entered credentials without saving.
// - "Test connection" REALLY attempts it: the relay opens a genuine SSH
//   session (see SandboxRelayTransport.probe). Success/failure is reported
//   honestly; relay-unreachable shows the plain-language 传话员 note plus
//   the copyable install steps (D18).
// - Local backend (iSH) is an honest deferred seam: `.unavailable` with
//   the nativeRequired note until P8 lands. Never faked.
//
// Zero emoji (SF Symbols only). All copy via L10n. All colors via DuduTheme.

/// Localize an i18n key, tolerating the relay error detail suffix.
/// Relay errors arrive as "sandbox.relay.unreachable: <detail>" — the key
/// portion is localized and the human detail is kept verbatim, so users
/// never see a bare sandbox.* key. Bare keys and non-key strings behave
/// exactly as before.
private func localizeKeyOrRaw(_ msg: String) -> String {
    let keyPattern = "^sandbox\\.[a-zA-Z.]+$"
    if msg.range(of: keyPattern, options: .regularExpression) != nil {
        return L10n.string(msg)
    }
    if let colon = msg.range(of: ": ") {
        let key = String(msg[..<colon.lowerBound])
        if key.range(of: keyPattern, options: .regularExpression) != nil {
            return "\(L10n.string(key)): \(msg[colon.upperBound...])"
        }
    }
    return msg
}

struct SandboxSettingsView: View {
    // @ObservedObject (not @StateObject): codebase pattern for @MainActor
    // singletons (cf. FontSettings.shared / AppearanceStudio.shared).
    @ObservedObject private var manager = SandboxManager.shared
    @State private var busy = false
    @State private var errorText: String? = nil
    @State private var relayMissing = false
    @State private var editing: SandboxServer? = nil
    @State private var addingNew = false
    @State private var pendingDelete: SandboxServer? = nil
    @State private var containers: [SandboxEnvironment] = []
    @State private var containersBusy = false
    @State private var webURL: IdentifiableURL? = nil

    private var cloudState: SandboxConnectionState { manager.cloudBackend.state }

    var body: some View {
        List {
            backendSection
            if manager.activeBackendId == .cloud {
                serversSection
                connectionSection
                if cloudState == .connected { containersSection }
            } else {
                localSection
            }
            crossAppSection
        }
        .duduCardList()
        .navigationTitle(L10n.string("sandbox.title"))
        .sheet(item: $editing) { server in
            ServerEditSheet(server: server, manager: manager) { refresh() }
        }
        .sheet(isPresented: $addingNew) {
            ServerEditSheet(server: nil, manager: manager) { refresh() }
        }
        .sheet(item: $webURL) { identified in
            InAppWebSheet(url: identified.url)
        }
        .confirmationDialog(
            L10n.string("sandbox.deleteServer"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button(L10n.string("common.delete"), role: .destructive) {
                if let s = pendingDelete { deleteServer(s) }
                pendingDelete = nil
            }
            Button(L10n.string("common.cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            if let s = pendingDelete {
                Text(L10n.format("sandbox.deleteServerConfirm", s.name))
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        // Re-read @Published state from the manager's backends.
        containers = []
        if cloudState == .connected { Task { await loadContainers() } }
    }

    // MARK: - Backend switcher (req 2: dual-mode, visible, persisted)

    private var backendSection: some View {
        Section {
            ForEach(SandboxBackendId.allCases, id: \.self) { id in
                BackendCardRow(
                    id: id,
                    active: manager.activeBackendId == id,
                    state: manager.connectionState(for: id),
                    detail: displayDetail(manager.stateDetail(for: id))
                ) {
                    selectBackend(id)
                }
            }
        } header: {
            DuduSectionTitle(L10n.string("sandbox.switchBackend"))
        } footer: {
            // Current mode is always visible, in words.
            DuduSectionFooter {
                Text(currentModeLine)
            }
        }
    }

    private var currentModeLine: String {
        let name = L10n.string(manager.activeBackendId.nameKey)
        let state = L10n.string(manager.connectionState(for: manager.activeBackendId).statusKey)
        return "\(name) · \(state)"
    }

    private func selectBackend(_ id: SandboxBackendId) {
        clearError()
        manager.setActiveBackend(id)
        refresh()
    }

    // MARK: - Servers (req 1)

    private var serversSection: some View {
        Section {
            if manager.servers.isEmpty {
                Text(L10n.string("sandbox.noServers"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            ForEach(manager.servers) { server in
                ServerRow(
                    server: server,
                    active: manager.activeServer?.id == server.id,
                    state: manager.activeServer?.id == server.id ? cloudState : .disconnected,
                    busy: busy,
                    onSelect: { selectServer(server) },
                    onEdit: { editing = server },
                    onDelete: { pendingDelete = server }
                )
            }
            Button {
                addingNew = true
            } label: {
                Label(L10n.string("sandbox.addServer"), systemImage: "plus")
                    .font(DuduTheme.bodyFont())
            }
            .disabled(busy)
        } header: {
            DuduSectionTitle(L10n.string("sandbox.servers"))
        } footer: {
            DuduSectionFooter {
                Text(L10n.string("sandbox.relayNote"))
            }
        }
    }

    private func selectServer(_ server: SandboxServer) {
        clearError()
        busy = true
        Task {
            do {
                try manager.setActiveServer(id: server.id)
                try await manager.connectActiveServer()
            } catch {
                reportError(error)
            }
            busy = false
            refresh()
        }
    }

    private func deleteServer(_ server: SandboxServer) {
        clearError()
        manager.deleteServer(id: server.id)
        refresh()
    }

    // MARK: - Connect / disconnect / relay steps

    private var connectionSection: some View {
        Section {
            if let errorText {
                Text(errorText)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduDestructive)
            }
            if relayMissing {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("sandbox.relayMissing"))
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    RelayInstallStepsView(host: manager.activeServer?.host ?? "")
                }
            }
            switch cloudState {
            case .connected:
                Button {
                    manager.disconnectActiveServer()
                    refresh()
                } label: {
                    Label(L10n.string("sandbox.disconnect"), systemImage: "bolt.slash.fill")
                }
                .disabled(busy)
            case .disconnected:
                if manager.activeServer != nil {
                    Button {
                        connectActive()
                    } label: {
                        Label(L10n.string("sandbox.connect"), systemImage: "bolt.fill")
                    }
                    .disabled(busy)
                }
            case .error, .unavailable:
                Button {
                    manager.resetBackend(.cloud)
                    clearError()
                    refresh()
                } label: {
                    Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            case .connecting:
                HStack {
                    ProgressView()
                    Text(L10n.string("sandbox.status.connecting"))
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        }
    }

    private func connectActive() {
        clearError()
        busy = true
        Task {
            do {
                try await manager.connectActiveServer()
            } catch {
                reportError(error)
            }
            busy = false
            refresh()
        }
    }

    // MARK: - Containers (real `docker ps`)

    private var containersSection: some View {
        Section {
            if containersBusy {
                HStack {
                    ProgressView()
                    Text(L10n.string("sandbox.containers"))
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            } else if containers.isEmpty {
                Text(L10n.string("sandbox.noContainers"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            ForEach(containers) { env in
                HStack(spacing: 10) {
                    Circle()
                        .fill(env.isRunning ? DuduTheme.success : DuduTheme.duduTextDim)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.name)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                        Text(env.image.map { "\(env.status) · \($0)" } ?? env.status)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Spacer()
                    Button {
                        toggleContainer(env)
                    } label: {
                        Image(systemName: env.isRunning ? "stop.fill" : "play.fill")
                            .foregroundStyle(env.isRunning ? DuduTheme.duduTextDim : DuduTheme.pink)
                    }
                    .disabled(busy)
                }
            }
        } header: {
            HStack {
                Text(L10n.string("sandbox.containers"))
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .textCase(nil)
                Spacer()
                Button {
                    Task { await loadContainers() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .disabled(containersBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DuduTheme.duduBackground)
        }
    }

    private func loadContainers() async {
        containersBusy = true
        defer { containersBusy = false }
        do {
            containers = try await manager.listEnvironments()
        } catch {
            reportError(error)
        }
    }

    private func toggleContainer(_ env: SandboxEnvironment) {
        busy = true
        Task {
            do {
                if env.isRunning {
                    try await manager.cloudBackend.stopEnvironment(id: env.id)
                } else {
                    try await manager.cloudBackend.startEnvironment(id: env.id)
                }
                containers = try await manager.listEnvironments()
            } catch {
                reportError(error)
            }
            busy = false
        }
    }

    // MARK: - Local backend (honest deferred seam)

    private var localSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: 30, height: 30)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("sandbox.backend.local"))
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(DuduTheme.duduTextDim)
                            .frame(width: 8, height: 8)
                        Text(L10n.string("sandbox.status.unavailable"))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Text(L10n.string("sandbox.local.nativeRequired"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            .padding(.vertical, 4)
            Button {
                manager.resetBackend(.local)
            } label: {
                Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                    .font(DuduTheme.bodyFont())
            }
        } header: {
            DuduSectionTitle(L10n.string("sandbox.backend.local"))
        }
    }

    // MARK: - Cross-app (req 3)

    private var crossAppSection: some View {
        Section {
            ForEach(OPEN_APP_WHITELIST, id: \.id) { entry in
                CrossAppRow(entry: entry) { url in
                    webURL = IdentifiableURL(url: url)
                }
            }
        } header: {
            DuduSectionTitle(L10n.string("crossapp.title"))
        } footer: {
            DuduSectionFooter {
                Text(L10n.string("crossapp.note"))
            }
        }
    }

    // MARK: - Error plumbing

    private func clearError() {
        errorText = nil
        relayMissing = false
    }

    /// Translate bare i18n keys (e.g. sandbox.cloud.noConfig). Relay errors
    /// arrive as "sandbox.relay.unreachable: <detail>" — the key portion is
    /// localized, the human detail kept verbatim; users never see a bare
    /// key. The relayMissing note below stays the human-readable part.
    /// Same rule as the old failConnect.
    private func reportError(_ error: Error) {
        let msg: String
        if let le = error as? LocalizedError, let d = le.errorDescription {
            msg = d
        } else {
            msg = error.localizedDescription
        }
        errorText = localizeKeyOrRaw(msg)
        relayMissing = (error as? SandboxRelayError)?.isUnreachable ?? false
    }

    /// Backend detail lines may be i18n keys, relay "key: detail" errors,
    /// or raw relay text.
    private func displayDetail(_ detail: String?) -> String? {
        guard let detail, !detail.isEmpty else { return nil }
        return localizeKeyOrRaw(detail)
    }
}

// MARK: - Backend card

private struct BackendCardRow: View {
    let id: SandboxBackendId
    let active: Bool
    let state: SandboxConnectionState
    let detail: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: id == .cloud ? "cloud" : "cpu")
                    .foregroundStyle(active ? DuduTheme.pink : DuduTheme.duduTextDim)
                    .frame(width: 30, height: 30)
                    .background(DuduTheme.duduIconChip)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string(id.nameKey))
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(L10n.string(state.statusKey))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    if let detail {
                        Text(detail)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.pink)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var statusColor: Color {
        switch state {
        case .connected: return DuduTheme.success
        case .connecting: return DuduTheme.warning
        case .error: return DuduTheme.duduDestructive
        case .disconnected, .unavailable: return DuduTheme.duduTextDim
        }
    }
}

// MARK: - Server row

private struct ServerRow: View {
    let server: SandboxServer
    let active: Bool
    let state: SandboxConnectionState
    let busy: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name)
                            .font(DuduTheme.bodyFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduText)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(active ? statusColor : DuduTheme.duduTextDim)
                                .frame(width: 8, height: 8)
                            Text(server.addressLine)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DuduTheme.pink)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .disabled(busy)
            .accessibilityLabel(L10n.string("sandbox.editServer"))
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .disabled(busy)
            .accessibilityLabel(L10n.string("common.delete"))
        }
        .padding(.vertical, 4)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var statusColor: Color {
        switch state {
        case .connected: return DuduTheme.success
        case .connecting: return DuduTheme.warning
        case .error: return DuduTheme.duduDestructive
        case .disconnected, .unavailable: return DuduTheme.duduTextDim
        }
    }
}

// MARK: - Server edit sheet (add / edit + real test-connection)

private struct ServerEditSheet: View {
    let server: SandboxServer?
    let manager: SandboxManager
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var authType: SandboxAuthType
    @State private var secret: String = ""
    @State private var busy = false
    @State private var testing = false
    @State private var errorText: String? = nil
    @State private var testOK = false

    init(server: SandboxServer?, manager: SandboxManager, onDone: @escaping () -> Void) {
        self.server = server
        self.manager = manager
        self.onDone = onDone
        _name = State(initialValue: server?.name ?? "")
        _host = State(initialValue: server?.host ?? "")
        _port = State(initialValue: server.map { String($0.port) } ?? "22")
        _username = State(initialValue: server?.username ?? "root")
        _authType = State(initialValue: server?.authType ?? .key)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("sandbox.serverName"), text: $name)
                    TextField(L10n.string("sandbox.host"), text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        TextField(L10n.string("sandbox.port"), text: $port)
                            .keyboardType(.numberPad)
                        TextField(L10n.string("sandbox.username"), text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Picker(L10n.string("sandbox.authType"), selection: $authType) {
                        Text(L10n.string("sandbox.authType.key")).tag(SandboxAuthType.key)
                        Text(L10n.string("sandbox.authType.password")).tag(SandboxAuthType.password)
                    }
                    .pickerStyle(.segmented)
                    if authType == .key {
                        TextField(
                            L10n.string("sandbox.privateKey"),
                            text: $secret,
                            axis: .vertical
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(4)
                    } else {
                        SecureField(L10n.string("sandbox.password"), text: $secret)
                    }
                    if server != nil {
                        Text(L10n.string("sandbox.secretKeepHint"))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                }
                if testOK {
                    Section {
                        Label(L10n.string("sandbox.testOk"), systemImage: "checkmark.circle.fill")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.success)
                    }
                }
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if testing { ProgressView() }
                            Label(
                                L10n.string("sandbox.testConnection"),
                                systemImage: "antenna.radiowaves.left.and.right"
                            )
                        }
                    }
                    .disabled(busy || testing)
                    Button {
                        save()
                    } label: {
                        Label(L10n.string("sandbox.saveAndConnect"), systemImage: "bolt.fill")
                    }
                    .disabled(busy || testing)
                } footer: {
                    DuduSectionFooter {
                        Text(L10n.string("sandbox.testConnectionNote"))
                    }
                }
            }
            .duduCardForm()
            .navigationTitle(
                server == nil ? L10n.string("sandbox.addServer") : L10n.string("sandbox.editServer")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) { dismiss() }
                }
            }
        }
    }

    private func draftServer() -> SandboxServer? {
        guard let portNum = Int(port.trimmingCharacters(in: .whitespaces)),
              (1 ... 65535).contains(portNum)
        else { return nil }
        return SandboxServer(
            id: server?.id ?? SandboxServer.newId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portNum,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: authType
        )
    }

    /// The REAL test: probes the entered credentials against the relay
    /// without saving anything.
    private func testConnection() {
        errorText = nil
        testOK = false
        guard let draft = draftServer(), draft.isValid else {
            errorText = L10n.string("sandbox.cloud.noConfig")
            return
        }
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        // New server, or switched auth type: the old secret (if any) no
        // longer applies — a fresh one is required. Editing with the same
        // auth type may leave it blank to keep the saved secret.
        let effectiveSecret: String
        if !trimmedSecret.isEmpty {
            effectiveSecret = trimmedSecret
        } else if let s = server, s.authType == authType {
            effectiveSecret = SandboxKeychain.loadSecret(for: s.id) ?? ""
        } else {
            errorText = L10n.string("sandbox.cloud.noConfig")
            return
        }
        testing = true
        Task {
            let result = await manager.testConnection(server: draft, secret: effectiveSecret)
            testing = false
            switch result {
            case .success:
                testOK = true
            case .failure(let e):
                let raw: String
                if let le = e as? LocalizedError, let d = le.errorDescription {
                    raw = d
                } else {
                    raw = e.localizedDescription
                }
                let shown = localizeKeyOrRaw(raw)
                errorText = "\(L10n.string("sandbox.testFailed")): \(shown)"
            }
        }
    }

    private func save() {
        errorText = nil
        guard let draft = draftServer(), draft.isValid else {
            errorText = L10n.string("sandbox.cloud.noConfig")
            return
        }
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSecret.isEmpty, server == nil || server?.authType != authType {
            errorText = L10n.string("sandbox.cloud.noConfig")
            return
        }
        busy = true
        Task {
            manager.saveServer(draft, secret: trimmedSecret.isEmpty ? nil : trimmedSecret)
            // Old onServerSaved: switch to it and connect right away.
            do {
                try manager.setActiveServer(id: draft.id)
                try await manager.connectActiveServer()
            } catch {
                // The server is saved either way; surface the connect error
                // on the main page instead of blocking the save.
            }
            busy = false
            onDone()
            dismiss()
        }
    }
}

// MARK: - Relay install steps (D18: the real path from "relay missing" to "relay running")

/// The exact install commands — copyable text she pastes into her server's
/// terminal herself. The Caddy snippet is pre-filled with this server's host.
private struct RelayInstallStepsView: View {
    let host: String
    @State private var open = false
    @State private var copiedKey: String? = nil

    private static let relayDownloadURL =
        "https://raw.githubusercontent.com/imcat-owo/dudu/main/sandbox-relay/relay.mjs"
    private static let relayPort = 18731

    private var installScript: String {
        [
            "mkdir -p /opt/dudu-sandbox && cd /opt/dudu-sandbox",
            "curl -sSL \(Self.relayDownloadURL) -o relay.mjs",
            "node --version  # needs node 18+",
            "PORT=\(Self.relayPort) HOST=127.0.0.1 node relay.mjs",
        ].joined(separator: "\n")
    }

    private var caddySnippet: String {
        let domain = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = domain.isEmpty ? "sandbox.example.com" : domain
        return "\(d) {\n    reverse_proxy 127.0.0.1:\(Self.relayPort)\n}"
    }

    private var systemdUnit: String {
        [
            "# save as /etc/systemd/system/dudu-sandbox-relay.service, then:",
            "#   sudo systemctl daemon-reload && sudo systemctl enable --now dudu-sandbox-relay",
            "",
            "[Unit]",
            "Description=dudu sandbox relay",
            "After=network.target",
            "",
            "[Service]",
            "ExecStart=/usr/bin/node /opt/dudu-sandbox/relay.mjs",
            "Environment=PORT=\(Self.relayPort) HOST=127.0.0.1",
            "Restart=always",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                open.toggle()
            } label: {
                Text(
                    open
                        ? L10n.string("sandbox.relayInstall.hideSteps")
                        : L10n.string("sandbox.relayInstall.showSteps")
                )
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.pink)
            }
            if open {
                Text(L10n.string("sandbox.relayInstall.runOnServer"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                stepRow(
                    key: "relay",
                    label: L10n.string("sandbox.relayInstall.stepRelay"),
                    text: installScript,
                    note: nil
                )
                stepRow(
                    key: "caddy",
                    label: L10n.string("sandbox.relayInstall.stepCaddy"),
                    text: caddySnippet,
                    note: L10n.string("sandbox.relayInstall.caddyNote")
                )
                stepRow(
                    key: "systemd",
                    label: L10n.string("sandbox.relayInstall.stepSystemd"),
                    text: systemdUnit,
                    note: nil
                )
            }
        }
    }

    private func stepRow(key: String, label: String, text: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    copiedKey = key
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedKey == key { copiedKey = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName: copiedKey == key
                                ? "checkmark" : "doc.on.doc"
                        )
                        Text(
                            copiedKey == key
                                ? L10n.string("sandbox.relayInstall.copied")
                                : L10n.string("common.copy")
                        )
                        .font(DuduTheme.captionFont())
                    }
                    .foregroundStyle(
                        copiedKey == key ? DuduTheme.success : DuduTheme.duduTextDim
                    )
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(DuduTheme.monoFont(size: 11))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(10)
            }
            .background(DuduTheme.duduCard)
            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            .overlay(
                RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                    .stroke(DuduTheme.duduDivider, lineWidth: 1)
            )
            if let note {
                Text(note)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
    }
}

// MARK: - Cross-app row (req 3)

/// One whitelist entry. No-param entries open on tap; entries with params
/// expand inline fields first, then open. Every tap really attempts the open
/// via CrossAppOpener (the apple-open engine's mechanism) — no dead buttons.
private struct CrossAppRow: View {
    let entry: OpenAppEntry
    /// Webview-mode entries stay inside 嘟嘟 — the parent presents the browser.
    let onWebView: (URL) -> Void

    @State private var expanded = false
    @State private var values: [String: String] = [:]
    @State private var opening = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if entry.needsParams {
                    expanded.toggle()
                } else {
                    attemptOpen()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: entry.mode == .webview ? "safari" : "arrow.up.right.square")
                        .foregroundStyle(DuduTheme.pink)
                        .frame(width: 30, height: 30)
                        .background(DuduTheme.duduIconChip)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.app)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                        if entry.mode == .webview {
                            Text(L10n.string("crossapp.inApp"))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    Spacer()
                    if opening {
                        ProgressView()
                    } else if entry.needsParams {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13))
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(opening)

            if expanded {
                ForEach(entry.params, id: \.name) { param in
                    TextField(
                        param.example,
                        text: Binding(
                            get: { values[param.name] ?? "" },
                            set: { values[param.name] = $0 }
                        )
                    )
                    .font(DuduTheme.bodyFont())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(DuduTheme.duduCard)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    .overlay(
                        RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                            .stroke(DuduTheme.duduDivider, lineWidth: 1)
                    )
                }
                Button {
                    attemptOpen()
                } label: {
                    Label(L10n.string("crossapp.open"), systemImage: "arrow.up.right.square")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                }
                .disabled(opening)
            }
            if let errorText {
                Text(errorText)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduDestructive)
            }
        }
        .padding(.vertical, 4)
    }

    private func attemptOpen() {
        errorText = nil
        opening = true
        do {
            let (resolved, destination) = try CrossAppOpener.resolve(entryId: entry.id, args: values)
            switch destination {
            case .jump(let url):
                Task { @MainActor in
                    switch await CrossAppOpener.open(url) {
                    case .opened:
                        break // She is now in the other app — nothing more to show.
                    case .notHandled:
                        errorText = L10n.format("openapp.error.notInstalled", resolved.app)
                    }
                    opening = false
                }
            case .webview(let url):
                opening = false
                onWebView(url)
            }
        } catch {
            if let le = error as? LocalizedError, let d = le.errorDescription {
                errorText = d
            } else {
                errorText = error.localizedDescription
            }
            opening = false
        }
    }
}

// MARK: - In-app browser sheet (webview-mode entries stay inside 嘟嘟)

private struct InAppWebSheet: View {
    let url: URL

    var body: some View {
        SafariView(url: url)
            .ignoresSafeArea()
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

// MARK: - Identifiable URL wrapper for .sheet(item:)

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
