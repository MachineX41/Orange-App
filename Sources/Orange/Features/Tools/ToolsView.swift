import OrangeKit
import SwiftUI

struct ToolsView: View {
    @Environment(AppRuntime.self) private var runtime
    var kind: MediaKind

    private var formats: [ConvertTarget] {
        let sample: String = switch kind {
        case .image: "a.png"
        case .video: "a.mp4"
        case .audio: "a.mp3"
        case .pdf: "a.pdf"
        default: "a.txt"
        }
        return Catalog.convertTargets(for: URL(fileURLWithPath: "/tmp/\(sample)"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: kind.title, subtitle: L("Pick a tool, then choose files, or drop files on the window first.", "Bir araç seçin, sonra dosya seçin ya da önce dosyaları pencereye bırakın."), symbol: kind.symbol)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(Catalog.tools(for: kind)) { tool in
                        Button {
                            runtime.request(tool)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.windowTitle).font(.system(size: 14, weight: .semibold))
                                    Text(tool.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if tool.minimumFiles > 1 {
                                    Text("2+").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                if !formats.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: L("Converts to", "Dönüştürülebilen biçimler"), symbol: "arrow.triangle.2.circlepath")
                        FlowLayout(spacing: 8) {
                            ForEach(formats) { target in
                                Text(target.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .glassEffect(.regular, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }
}
