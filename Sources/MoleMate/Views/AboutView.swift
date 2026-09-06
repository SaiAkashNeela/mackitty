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
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                AppLogoView(size: 72)
                    .shadow(color: Color.blue.opacity(0.35), radius: 14, y: 4)

                VStack(spacing: 4) {
                    Text("MacKitty")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("A calmer, cleaner Mac")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("Version 1.0.0 (Build 2026.09)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 2)
                }
            }

            Text("MacKitty is a fast, transparent macOS cleaner and hardware monitor designed with zero bloat and zero telemetry. Powered by Mole CLI to safely clean caches, developer leftovers, logs, and unused clutter.")
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)

            // Contact and Links
            VStack(spacing: 8) {
                LinkRow(icon: "globe", label: "Website", value: "mackitty.com", urlString: "https://mackitty.com")
                LinkRow(icon: "envelope.fill", label: "Email Support", value: "hello@mackitty.com", urlString: "mailto:hello@mackitty.com")
                LinkRow(icon: "terminal.fill", label: "CLI Engine", value: "Mole (Homebrew)", urlString: "https://github.com/tw93/mole")
            }
            .padding(12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            }

            // Update status section
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(updater.statusMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(updater.isUpdateAvailable ? .yellow : .white.opacity(0.6))
                    Text("Checked: \(updater.lastCheckedText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer()

                if updater.isUpdateAvailable {
                    Button("Update") { updater.openDownloadPage() }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.blue, in: Capsule())
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
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(updater.isChecking)
                }
            }
            .padding(.horizontal, 4)

            Text("© 2026 MacKitty. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1))
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
                    .foregroundStyle(Color.blue)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
    }
}
