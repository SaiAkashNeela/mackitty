import SwiftUI
import AppKit

struct ScanPermissionModalView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.blue)
            }
            .padding(.top, 4)

            VStack(spacing: 5) {
                Text("Safe System Inspection")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text("macOS System Permissions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Info rows
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orange)
                        .frame(width: 20)
                        .padding(.top, 2)

                    Text("You will be getting popups from macOS asking to allow or disallow access to system and cache folders.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.green)
                        .frame(width: 20)
                        .padding(.top, 2)

                    Text("Make sure to click Allow so that MacKitty can scan properly.")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 20)
                        .padding(.top, 2)

                    Text("Don't worry — nothing will be deleted. This is only a preview scan to inspect safe cleanup areas.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
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
        .frame(width: 420)
        .background(Color(red: 0.11, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1))
        }
    }
}
