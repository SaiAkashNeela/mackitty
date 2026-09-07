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
                    .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("MacKitty Update")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        Text("v\(updater.latestVersion)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.35), lineWidth: 0.8))
                    }

                    Text("Current version: v\(updater.currentVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }

            // Description / Release notes box
            VStack(alignment: .leading, spacing: 8) {
                Text("What's New")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !updater.releaseNotes.isEmpty {
                            Text(updater.releaseNotes)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineSpacing(3)
                        } else {
                            Text("• Universal Apple Silicon and Intel optimizations\n• Performance and cache scanning improvements\n• Hardened runtime and Apple security updates")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineSpacing(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 90)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

            // Progress or Action Section
            if updater.isInstalling {
                VStack(spacing: 10) {
                    ProgressView(value: updater.installProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(Color.blue)

                    HStack {
                        Text(updater.installStatusText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
            } else if let errorMsg = updater.installError {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Installation Notice")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(errorMsg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Buttons
            HStack(spacing: 10) {
                if !updater.isInstalling {
                    Button(action: { updater.openDownloadPage() }) {
                        Text("Download .dmg Manually")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(updater.isInstalling)

                Button(action: {
                    updater.startInPlaceUpdate()
                }) {
                    HStack(spacing: 6) {
                        if updater.isInstalling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(updater.isInstalling ? "Updating…" : "Update & Restart")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(updater.isInstalling)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        .preferredColorScheme(.dark)
    }
}
