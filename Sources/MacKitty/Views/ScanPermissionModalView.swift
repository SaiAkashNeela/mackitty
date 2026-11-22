import SwiftUI
import AppKit

struct ScanPermissionModalView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

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

                Text("macOS Permissions")
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
