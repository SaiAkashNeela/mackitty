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
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.blue)
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("Safe System Inspection")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text("macOS Permissions & Engine Setup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Permission info rows
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.orange)
                        .frame(width: 18)
                        .padding(.top, 2)

                    Text("macOS will prompt for folder access to inspect safe cache and build directories.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.green)
                        .frame(width: 18)
                        .padding(.top, 2)

                    Text("Click Allow on system prompts so MacKitty can accurately report recoverable space.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 18)
                        .padding(.top, 2)

                    Text("Zero files are deleted during this preview scan. Your personal documents are never touched.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            }

            // 1-Shot Homebrew + Mole CLI Installer (shown if Mole is not detected)
            if !model.mole.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.cyan)
                        Text("Optional: Install Homebrew & Mole CLI (1-Shot)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }

                    Text("MacKitty works out-of-the-box via its native Swift engine. If you want Homebrew and Mole CLI installed, run this 1-shot command:")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(oneShotInstallCommand)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

                        Button(copiedCommand ? "Copied!" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(oneShotInstallCommand, forType: .string)
                            copiedCommand = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                copiedCommand = false
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedCommand ? Color.green : Color.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                            .foregroundStyle(Color.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.15))
                }
            }

            // Reassurance Pill
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
                Text("No personal data or files are ever deleted")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
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
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 480)
        .background(Color(red: 0.11, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1))
        }
    }
}
