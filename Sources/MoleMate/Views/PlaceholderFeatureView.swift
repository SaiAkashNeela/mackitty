import SwiftUI

struct PlaceholderFeatureView: View {
    @EnvironmentObject private var model: DashboardModel
    let section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Image(systemName: section.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 52, height: 52)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Powered by Mole")
                        .font(.system(size: 15, weight: .semibold))
                    Text("This surface is next in the build. The navigation and visual system are ready for the real Mole data flow.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            Button("Back to Home") { model.selectedSection = .home }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            Spacer()
        }
        .padding(38)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.42))
    }

    private var subtitle: String {
        switch section {
        case .manageApps: "Uninstall apps and clean their leftovers."
        case .largeFiles: "Find the files quietly taking up your disk."
        case .duplicates: "Review duplicate files before they become clutter."
        case .startupItems: "Understand what launches with your Mac."
        case .diskUsage: "See where your storage is going."
        case .settings: "Tune MacKitty to your workflow."
        default: "A focused view for keeping your Mac healthy."
        }
    }
}
