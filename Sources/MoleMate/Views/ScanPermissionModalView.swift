import SwiftUI
import AppKit

struct ScanPermissionModalView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var copiedCommand: Bool = false

    private let oneShotInstallCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && brew install mole"

    var body: some View {
        VStack(spacing: 16) {
            // Header icon
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("Safe System Inspection")
                    .font(Theme.display(18, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("macOS Permissions & Engine Setup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Permission info rows
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.warning)
                        .frame(width: 18)
                        .padding(.top, 2)

                    Text("macOS will prompt for folder access to inspect safe cache and build directories.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.success)
                        .frame(width: 18)
                        .padding(.top, 2)

                    Text("Click Allow on system prompts so MacKitty can accurately report recoverable space.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.info)
                        .frame(width: 18)
                        .padding(.top, 2)

                    Text("Zero files are deleted during this preview scan. Your personal documents are never touched.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .glassPanel(radius: 10)

            // 1-Shot Homebrew + Mole CLI Installer (shown if Mole is not detected)
            if !model.mole.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.info)
                        Text("Optional: Install Homebrew & Mole CLI (1-Shot)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Text("MacKitty works out-of-the-box via its native Swift engine. If you want Homebrew and Mole CLI installed, run this 1-shot command:")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(oneShotInstallCommand)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.canvasDeep, in: RoundedRectangle(cornerRadius: 6))

                        Button(copiedCommand ? "Copied!" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(oneShotInstallCommand, forType: .string)
                            copiedCommand = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                copiedCommand = false
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedCommand ? Theme.success : Theme.accentStrong)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong))
                        .buttonStyle(.plain)

                        Button {
                            let escaped = oneShotInstallCommand.replacingOccurrences(of: "\"", with: "\\\"")
                            let script = """
                            tell application "Terminal"
                                activate
                                do script "\(escaped)"
                            end tell
                            """
                            NSAppleScript(source: script)?.executeAndReturnError(nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Run in Terminal")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Theme.info)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Theme.info.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.info.opacity(0.25))
                }
            }

            // Reassurance Pill
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.success)
                Text("No personal data or files are ever deleted")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.lineStrong))
                .buttonStyle(.plain)

                Button(action: {
                    dismiss()
                    model.startScanAfterPermissionPrompt()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Continue & Scan")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line)
        }
    }
}
