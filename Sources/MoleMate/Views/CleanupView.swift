import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var showConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clean")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Review Mole’s cleanup plan before you apply it.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 23))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview-first cleanup")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Mole validates paths and skips anything it cannot prove is safe to change.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ready to scan")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Start with a dry run. No files are changed.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Preview Cleanup") { model.scan() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(model.isScanning)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                if !model.lastOperationOutput.isEmpty {
                    OperationOutputView(output: model.lastOperationOutput)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Apply cleanup")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("This runs `mo clean` and may remove files selected by Mole.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Cleanup", role: .destructive) { showConfirmation = true }
                        .buttonStyle(.bordered)
                        .disabled(model.isCleaning || model.lastOperationOutput.isEmpty)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(38)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.42))
        .confirmationDialog("Run Mole cleanup?", isPresented: $showConfirmation) {
            Button("Run Cleanup", role: .destructive) { model.clean() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Mole will perform the cleanup operation after its own safety checks. Review the dry-run output first.")
        }
    }
}

private struct OperationOutputView: View {
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mole output", systemImage: "terminal")
                .font(.system(size: 14, weight: .semibold))
            ScrollView {
                Text(output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 230)
        }
        .padding(18)
        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
