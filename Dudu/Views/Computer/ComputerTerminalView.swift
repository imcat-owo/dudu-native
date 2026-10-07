import SwiftUI

// MARK: - D23 · computer terminal UI
//
// Native port of the old app's Terminal tab (openmuse/apps/mobile/src/
// computer-workspace.tsx): a status card, scrollable monospace output,
// command receipts with exit codes, and an input row with a send button.
//
// Genuinely wired to ComputerBackend (Views/Computer/ComputerBackend.swift):
// pre-P8 the iSH seams are nil, so the status card shows the honest pending
// notice, the input is disabled, and Start throws the real
// DuduKernelBootError.sandboxUnavailable — nothing is simulated. The Files
// tab from the old app is intentionally NOT ported: it needs the P8 fakefs
// file APIs, which don't exist yet; a file browser against no backend would
// be fake UI (see the D23 report).
//
// Zero emoji (SF Symbols only). All colors via DuduTheme. All copy via the
// D13 trilingual catalog (computer.* / term.* keys).

struct ComputerTerminalView: View {
    @StateObject private var viewModel = ComputerTerminalViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DuduTheme.pagePadding) {
                        statusCard
                            .id("computerTop")
                        if let error = viewModel.errorMessage {
                            errorCard(error)
                        }
                        terminalSection
                        agentHistorySection
                    }
                    .padding(DuduTheme.pagePadding)
                }
                .onChange(of: viewModel.records.first?.id) { _, _ in
                    withAnimation {
                        proxy.scrollTo("computerTop", anchor: .top)
                    }
                }
            }
            inputBar
        }
        .background(DuduTheme.duduBackground)
        .navigationTitle(L10n.string("computer.sheetTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    // MARK: - Status card (old app's header card)

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DuduTheme.duduIconChip)
                        .frame(width: 40, height: 40)
                    Image(systemName: "terminal")
                        .font(.system(size: FontSettings.shared.scaledApp(18), weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("term.title"))
                        .font(DuduTheme.titleFont())
                        .foregroundStyle(DuduTheme.duduText)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.status == .running ? DuduTheme.pink : DuduTheme.duduTextDim)
                            .frame(width: 8, height: 8)
                        Text(statusLine)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                Spacer()
            }
            if viewModel.status == .pending {
                Text(L10n.string("computer.backendPendingDetail"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            if viewModel.status != .pending {
                HStack(spacing: 8) {
                    if viewModel.status == .running {
                        Button {
                            viewModel.stopComputer()
                        } label: {
                            Label(L10n.string("term.stop"), systemImage: "power")
                        }
                        .buttonStyle(ComputerButtonStyle(primary: false))
                        .disabled(viewModel.busy)
                    } else {
                        Button {
                            viewModel.startComputer()
                        } label: {
                            Label(L10n.string("term.start"), systemImage: "play.fill")
                        }
                        .buttonStyle(ComputerButtonStyle(primary: true))
                        .disabled(viewModel.busy)
                    }
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label(L10n.string("computer.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ComputerButtonStyle(primary: false))
                    .disabled(viewModel.busy)
                }
            }
        }
        .padding(DuduTheme.pagePadding)
        .background(DuduTheme.duduCard)
        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private var statusLine: String {
        switch viewModel.status {
        case .pending: return L10n.string("computer.backendPending")
        case .running: return L10n.string("term.running")
        case .stopped: return L10n.string("term.stopped")
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DuduTheme.duduDestructive)
            Text(message)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            Spacer()
            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .padding(DuduTheme.pagePadding)
        .background(DuduTheme.duduCard)
        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: - Terminal output (old app's command receipts)

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.records.isEmpty {
                if viewModel.status == .running {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: FontSettings.shared.scaledApp(28)))
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Text(L10n.string("term.readyTitle"))
                            .font(DuduTheme.titleFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Text(L10n.string("term.readyDetail"))
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                ForEach(viewModel.records) { record in
                    ComputerCommandReceiptView(record: record)
                }
            }
            if viewModel.commandRunning {
                Text(L10n.string("term.runningNote"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Text(L10n.string("term.runNote"))
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    // MARK: - Agent shell history (COMPUTER.md: "inspect what the agent ran")

    private var agentHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.agentHistory.isEmpty {
                Text(L10n.string("computer.agentHistory"))
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Text(L10n.string("computer.agentHistoryDetail"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                ForEach(viewModel.agentHistory, id: \.index) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("$ \(entry.command)")
                            .font(DuduTheme.monoFont(size: 12))
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(3)
                        HStack(spacing: 8) {
                            if let code = entry.exitCode {
                                Text(L10n.format("term.exitCode", code))
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(code == 0 ? DuduTheme.duduTextDim : DuduTheme.duduDestructive)
                            }
                            Text(computerTimeLabel(entry.startedAt))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        if let note = entry.exitNote, !note.isEmpty {
                            Text(note)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DuduTheme.duduCard)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                }
            }
        }
    }

    // MARK: - Input row

    private var inputBar: some View {
        VStack(spacing: 8) {
            if hasCurlyQuotes {
                Button(L10n.string("term.useStraightQuotes")) {
                    viewModel.commandText = viewModel.commandText
                        .replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
                        .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
                }
                .buttonStyle(ComputerButtonStyle(primary: false))
            }
            HStack(spacing: 8) {
                TextField(L10n.string("term.commandPlaceholder"), text: $viewModel.commandText)
                    .font(DuduTheme.monoFont(size: 13))
                    .foregroundStyle(DuduTheme.duduText)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(DuduTheme.duduCard)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    .disabled(viewModel.status != .running)
                    .onSubmit { viewModel.run() }
                Button {
                    viewModel.run()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: FontSettings.shared.scaledApp(16), weight: .medium))
                        .foregroundStyle(DuduTheme.cream)
                        .frame(width: 40, height: 40)
                        .background(viewModel.canRun ? DuduTheme.pink : DuduTheme.duduDivider)
                        .clipShape(Circle())
                }
                .disabled(!viewModel.canRun)
            }
        }
        .padding(.horizontal, DuduTheme.pagePadding)
        .padding(.vertical, 10)
        .background(DuduTheme.duduBackground)
    }

    private var hasCurlyQuotes: Bool {
        viewModel.commandText.contains(where: { "‘’“”".contains($0) })
    }
}

// MARK: - Command receipt (old app's CommandReceipt)

private struct ComputerCommandReceiptView: View {
    let record: ComputerCommandRecord
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(statusText)
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(computerTimeLabel(record.startedAt))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Text("$ \(record.command)")
                .font(DuduTheme.monoFont(size: 13))
                .foregroundStyle(DuduTheme.duduText)
                .textSelection(.enabled)
            if expanded {
                if !record.output.isEmpty {
                    Text(record.output)
                        .font(DuduTheme.monoFont(size: 12))
                        .foregroundStyle(DuduTheme.duduText)
                        .textSelection(.enabled)
                } else if record.status != .running {
                    Text(L10n.string("term.noOutput"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                if record.truncated {
                    Text(L10n.string("term.truncatedNote"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            if !record.output.isEmpty {
                Button(expanded ? L10n.string("term.hideOutput") : L10n.string("term.showOutput")) {
                    expanded.toggle()
                }
                .buttonStyle(ComputerButtonStyle(primary: false))
            }
        }
        .padding(DuduTheme.pagePadding)
        .background(DuduTheme.duduCard)
        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private var statusText: String {
        let word: String
        switch record.status {
        case .running: word = L10n.string("term.statusRunning")
        case .succeeded: word = L10n.string("term.statusSucceeded")
        case .failed: word = L10n.string("term.statusFailed")
        }
        if let code = record.exitCode {
            return word + " · " + L10n.format("term.exitCode", code)
        }
        return word
    }

    @MainActor
    private var statusColor: Color {
        switch record.status {
        case .running: return DuduTheme.pink
        case .succeeded: return DuduTheme.duduTextDim
        case .failed: return DuduTheme.duduDestructive
        }
    }
}

// MARK: - Local button style (DuduTheme tokens only)

@MainActor
private struct ComputerButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DuduTheme.bodyFont(weight: .semibold))
            .foregroundStyle(primary ? DuduTheme.cream : DuduTheme.duduText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(primary ? DuduTheme.pink : DuduTheme.duduIconChip)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Time labels (file scope so both views share them)

private func computerTimeLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return computerTimeFormatter.string(from: date)
    }
    return computerDateTimeFormatter.string(from: date)
}

private let computerTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
}()

private let computerDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .short
    return f
}()
