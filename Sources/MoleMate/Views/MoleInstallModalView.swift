import SwiftUI
import AppKit

struct MoleInstallModalView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var copiedToClipboard = false

    var body: some View {
        VStack(spacing: 20) {
            // Header icon
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 58, height: 58)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 6)

            VStack(spacing: 5) {
                Text("Optional Power Engine: Mole CLI")
                    .font(Theme.display(18, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Developer Command-Line Companion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Explanatory card
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.success)
                        .frame(width: 20)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Native Swift Engine Active")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("MacKitty works out-of-the-box with pure Swift. You can clean safe caches and recover gigabytes immediately without installing any tools.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.warning)
                        .frame(width: 20)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Install via Homebrew (Optional)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("If you use Homebrew and want CLI integration in your terminal, run:")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)

                        HStack {
                            Text("brew install mole")
                                .font(Theme.mono(11.5))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.canvasDeep, in: RoundedRectangle(cornerRadius: 6))

                            Button(copiedToClipboard ? "Copied!" : "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install mole", forType: .string)
                                copiedToClipboard = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    copiedToClipboard = false
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copiedToClipboard ? Theme.success : Theme.accentStrong)
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(14)
            .glassPanel(radius: 10)

            // Action buttons
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        // Open Terminal running brew install mole
                        let script = """
                        tell application "Terminal"
                            activate
                            do script "brew install mole"
                        end tell
                        """
                        NSAppleScript(source: script)?.executeAndReturnError(nil)
                        UserDefaults.standard.set(true, forKey: "didPromptMoleInstall")
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Install via Terminal")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)

                    Button {
                        UserDefaults.standard.set(true, forKey: "didPromptMoleInstall")
                        dismiss()
                    } label: {
                        Text("Use Native Swift Engine")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.lineStrong))
                    }
                    .buttonStyle(.plain)
                }

                Button("Don't ask again") {
                    UserDefaults.standard.set(true, forKey: "didPromptMoleInstall")
                    dismiss()
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line)
        }
    }
}
