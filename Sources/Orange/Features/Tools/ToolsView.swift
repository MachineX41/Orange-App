import OrangeKit
import SwiftUI

struct ToolsView: View {
    @Environment(AppRuntime.self) private var runtime

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.tools)
                        .font(.system(size: 28, weight: .semibold))
                    Text(Copy.toolsLead)
                        .font(.system(size: 16, weight: .medium))
                    Text(Copy.toolsSub)
                        .font(.system(size: 13))
                        .foregroundStyle(OrangeTheme.muted)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                Text(Copy.ready.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(OrangeTheme.accent)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(ToolID.allCases.enumerated()), id: \.element) { index, tool in
                        Button {
                            runtime.request(tool)
                        } label: {
                            toolCard(
                                number: index + 1,
                                symbol: Copy.symbol(for: tool),
                                title: Copy.toolTitle(tool),
                                summary: Copy.toolSummary(tool),
                                badge: Copy.ready
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(Copy.planned.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(OrangeTheme.muted)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(PlannedTool.allCases) { tool in
                        toolCard(
                            number: nil,
                            symbol: Copy.symbol(for: tool),
                            title: Copy.plannedTitle(tool),
                            summary: Copy.plannedSummary(tool),
                            badge: Copy.planned
                        )
                        .opacity(0.72)
                    }
                }
            }
            .padding(36)
            .padding(.top, 8)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func toolCard(number: Int?, symbol: String, title: String, summary: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrangeTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(OrangeTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                if let number {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OrangeTheme.muted)
                }
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OrangeTheme.canvas)
                    .clipShape(Capsule())
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OrangeTheme.ink)
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(OrangeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .orangeCard(radius: 20)
    }
}
