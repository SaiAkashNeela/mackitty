import SwiftUI
import AppKit

struct UpdateModalView: View {
    @ObservedObject var updater: UpdateCheckerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header with App Icon and Version Pill
            HStack(spacing: 14) {
                AppLogoView(size: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("MacKitty Update")
                            .font(Theme.display(16, .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("v\(updater.latestVersion)")
                            .font(Theme.mono(11, .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.14))
                            .foregroundStyle(Theme.success)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Theme.success.opacity(0.35), lineWidth: 0.8))
                    }

                    Text("Current version: v\(updater.currentVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            // Description / Release notes box
            VStack(alignment: .leading, spacing: 8) {
                Text("What's New")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !updater.releaseNotes.isEmpty {
                            Text(updater.releaseNotes)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                                .lineSpacing(3)
                        } else {
                            Text("• Universal Apple Silicon and Intel optimizations\n• Performance and cache scanning improvements\n• Hardened runtime and Apple security updates")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                                .lineSpacing(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 90)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            }

            // Progress or Action Section
            if updater.isInstalling {
                VStack(spacing: 10) {
                    ProgressView(value: updater.installProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)

                    HStack {
                        Text(updater.installStatusText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            } else if let errorMsg = updater.installError {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("Installation Notice")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(errorMsg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warning.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Buttons
            HStack(spacing: 10) {
                if !updater.isInstalling {
                    Button("Download manually") { updater.openDownloadPage() }
                        .buttonStyle(.plain)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Spacer(minLength: 8)

                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .lineLimit(1)
                    .fixedSize()
                    .disabled(updater.isInstalling)
                    .keyboardShortcut(.cancelAction)

                Button(action: { updater.startInPlaceUpdate() }) {
                    HStack(spacing: 6) {
                        if updater.isInstalling {
                            ProgressView().controlSize(.small)
                        }
                        Text(updater.isInstalling ? "Updating…" : "Update & Restart")
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !updater.isInstalling))
                .disabled(updater.isInstalling)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.canvas)
        .preferredColorScheme(.light)
    }
}
