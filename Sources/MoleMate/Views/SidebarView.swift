import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: DashboardModel

    private let mainSections: [AppSection] = [.home, .clean, .manageApps, .largeFiles, .duplicates, .startupItems, .diskUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppLogoView(size: 46, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacKitty")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("A calmer, cleaner Mac")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)

            VStack(spacing: 5) {
                ForEach(mainSections) { section in
                    SidebarRow(section: section, isSelected: model.selectedSection == section) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Divider()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            SidebarRow(section: .settings, isSelected: model.selectedSection == .settings) {
                model.selectedSection = .settings
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
        }
        .background(.thinMaterial)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                Text(section.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.green.opacity(0.13) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
