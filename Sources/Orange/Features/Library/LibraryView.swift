import AppKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var query = ""

    private var results: [JobRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return runtime.jobs }
        return runtime.jobs.filter {
            $0.title.lowercased().contains(text) || $0.detail.lowercased().contains(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(Copy.library)
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                TextField(Copy.search, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)

            if results.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(OrangeTheme.accent)
                    Text(Copy.emptyLibrary)
                        .foregroundStyle(OrangeTheme.muted)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { job in
                            HStack(spacing: 12) {
                                status(job.state)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(job.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(job.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(OrangeTheme.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(job.createdAt, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundStyle(OrangeTheme.muted)
                                if !job.outputPaths.isEmpty {
                                    Button(Copy.reveal) {
                                        NSWorkspace.shared.activateFileViewerSelecting(
                                            job.outputPaths.map { URL(fileURLWithPath: $0) }
                                        )
                                    }
                                    .buttonStyle(OrangeButtonStyle(prominent: false))
                                }
                            }
                            .padding(14)
                            .orangeCard(radius: 16)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func status(_ state: JobState) -> some View {
        Group {
            switch state {
            case .running:
                ProgressView().controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OrangeTheme.accent)
            case .failure:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color(hex: 0xB42318))
            }
        }
        .frame(width: 22, height: 22)
    }
}
