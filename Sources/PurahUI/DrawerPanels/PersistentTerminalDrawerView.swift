// Sources/PurahUI/DrawerPanels/PersistentTerminalDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct PersistentTerminalDrawerView: View {
    public let store: PurahWorkspaceStore

    @State private var inputCommand: String = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1

    private var terminal: PersistentTerminalService {
        PersistentTerminalService.shared
    }

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var terminalColor: Color {
        palette.podColor(for: "terminal", store: store)
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Status & Utility Toolbar
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(terminal.isRunning ? Color.green : Color.red)
                        .frame(width: 5, height: 5)

                    Text(terminal.shellName.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(terminalColor.opacity(0.18))
                        .foregroundColor(terminalColor)
                        .cornerRadius(3)

                    if !terminal.isRunning {
                        Text("EXITED")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                // Quick Terminal Buttons
                Button {
                    terminal.sendInterrupt()
                } label: {
                    Text("^C")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Send SIGINT (Ctrl+C)")

                Button {
                    terminal.clearScreen()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Terminal Buffer")

                Button {
                    terminal.restartSession()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Restart Shell Session")
            }
            .padding(.bottom, 2)

            // Row 2: Live Terminal Screen
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cleanTerminalText(terminal.terminalOutput.isEmpty ? "Purah Terminal [\(terminal.shellName)]\nType commands below or press Return..." : terminal.terminalOutput))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(palette.style == .native ? Color.primary : Color.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("bottomAnchor")
                    }
                    .padding(6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                )
                .onChange(of: terminal.terminalOutput) {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)

            // Row 3: Command Input Row
            HStack(spacing: 5) {
                Text("❯")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(terminalColor)

                TextField("Type command...", text: $inputCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.primary)
                    .onSubmit {
                        executeCommand()
                    }

                if !inputCommand.isEmpty {
                    Button {
                        executeCommand()
                    } label: {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(terminalColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
            )

            // Quick command shortcut chips
            HStack(spacing: 4) {
                quickChip("ls -la")
                quickChip("git status")
                quickChip("top -l 1")
                quickChip("clear")
            }
        }
        .onAppear {
            terminal.setDrawerActive(true)
        }
        .onDisappear {
            terminal.setDrawerActive(false)
        }
    }

    private func quickChip(_ cmd: String) -> some View {
        Button {
            terminal.sendInput(cmd + "\r")
        } label: {
            Text(cmd)
                .font(.system(size: 7.5, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .foregroundColor(.secondary)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    private func executeCommand() {
        let trimmed = inputCommand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            terminal.sendInput("\r")
            return
        }

        commandHistory.append(trimmed)
        terminal.sendInput(trimmed + "\r")
        inputCommand = ""
        historyIndex = -1
    }

    private func cleanTerminalText(_ raw: String) -> String {
        // Strip common cursor positioning & control escape codes for clean crisp terminal output
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        // Regex strip ANSI escape sequences: \u{1b}\[[0-9;]*[a-zA-Z]
        if let regex = try? NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[a-zA-Z]", options: []) {
            let range = NSRange(location: 0, length: text.utf16.count)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }

        return text
    }
}
