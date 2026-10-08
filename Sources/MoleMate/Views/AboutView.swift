import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var updater = UpdateCheckerService()

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                Spacer()
                Button(action: {
                    dismiss()
                    if let keyWindow = NSApp.keyWindow, keyWindow.title == "About MacKitty" {
                        keyWindow.close()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                AppLogoView(size: 72)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 14, y: 4)

                VStack(spacing: 4) {
                    Text("MacKitty")
                        .font(Theme.display(24, .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("A calmer, cleaner Mac")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    Text("Version 1.0.0 (Build 2026.09)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 2)
                }
            }

            Text("MacKitty is a fast, transparent macOS cleaner and hardware monitor designed with zero bloat and zero telemetry. Powered by Mole CLI to safely clean caches, developer leftovers, logs, and unused clutter.")
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)

            // Contact and Links
            VStack(spacing: 8) {
                LinkRow(icon: "globe", label: "Website", value: "mackitty.com", urlString: "https://mackitty.com")
                LinkRow(icon: "envelope.fill", label: "Email Support", value: "hello@mackitty.com", urlString: "mailto:hello@mackitty.com")
                LinkRow(icon: "terminal.fill", label: "CLI Engine", value: "Mole (Homebrew)", urlString: "https://github.com/tw93/mole")
            }
            .padding(12)
            .glassPanel(radius: 10)

            // Update status section (App Store builds are updated by the App Store)
            #if !APPSTORE
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(updater.statusMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(updater.isUpdateAvailable ? Theme.accentStrong : Theme.textSecondary)
                    Text("Checked: \(updater.lastCheckedText)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if updater.isUpdateAvailable {
                    Button("Update Now") { updater.openUpdateFlow() }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                        .buttonStyle(.plain)
                } else {
                    Button(action: {
                        Task { await updater.checkForUpdates() }
                    }) {
                        HStack(spacing: 4) {
                            if updater.isChecking {
                                ProgressView().scaleEffect(0.5)
                            }
                            Text(updater.isChecking ? "Checking…" : "Check Updates")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong))
                    }
                    .buttonStyle(.plain)
                    .disabled(updater.isChecking)
                }
            }
            .padding(.horizontal, 4)
            #endif

            Text("© 2026 MacKitty. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(28)
        .frame(width: 440)
        .background(Theme.canvas)
        .preferredColorScheme(.light)
        .sheet(isPresented: $updater.showUpdateModal) {
            UpdateModalView(updater: updater)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line)
        }
    }
}

private struct LinkRow: View {
    let icon: String
    let label: String
    let value: String
    let urlString: String

    var body: some View {
        Button(action: {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
