import AppKit
import OrangeKit
import SwiftUI

struct EditorSheet: View {
    var route: SheetRoute

    var body: some View {
        switch route {
        case .compress(let files):
            CompressSheet(files: files)
        case .resize(let file):
            ResizeSheet(file: file)
        case .crop(let file):
            CropSheet(file: file)
        case .rotate(let file):
            RotateSheet(file: file)
        case .split(let file):
            SplitSheet(file: file)
        }
    }
}

private struct SheetHeader: View {
    var title: String
    var subtitle: String
    var saveTitle: String
    var canSave: Bool
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(OrangeTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button(Copy.cancel) { dismiss() }
                .buttonStyle(OrangeButtonStyle(prominent: false))
            Button(saveTitle) { onSave() }
                .buttonStyle(OrangeButtonStyle(prominent: true))
                .disabled(!canSave)
        }
    }
}

private struct CompressSheet: View {
    var files: [FileRef]
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var quality: Double

    init(files: [FileRef]) {
        self.files = files
        _quality = State(initialValue: AppRuntime.shared.jpegQuality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(
                title: Copy.toolTitle(.compress),
                subtitle: Copy.count(files.count),
                saveTitle: Copy.saveCopy,
                canSave: true
            ) {
                runtime.exportCompressed(files, quality: quality)
                dismiss()
            }
            Text("\(Copy.quality)  \(Int(quality * 100))%")
                .font(.system(size: 13, weight: .semibold))
            Slider(value: $quality, in: 0.35...0.95)
            Text(Copy.toolSummary(.compress))
                .font(.system(size: 13))
                .foregroundStyle(OrangeTheme.muted)
            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 280)
        .background(OrangeTheme.canvas)
    }
}

private struct ResizeSheet: View {
    var file: FileRef
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var pixelSize: CGSize = .zero
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var lockAspect = true
    @State private var format: ConvertTarget = .jpeg
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                title: Copy.toolTitle(.resize),
                subtitle: file.name,
                saveTitle: Copy.saveCopy,
                canSave: parsedSize != nil
            ) {
                guard let size = parsedSize else { return }
                runtime.exportImage(
                    file,
                    operation: .resize(width: size.width, height: size.height),
                    format: format,
                    quality: runtime.jpegQuality
                )
                dismiss()
            }
            preview
            HStack(spacing: 12) {
                field(Copy.width, text: widthBinding)
                field(Copy.height, text: heightBinding)
            }
            Toggle(Copy.lockAspect, isOn: $lockAspect)
            Picker(Copy.format, selection: $format) {
                ForEach(ConvertTarget.allCases.filter(\.isRaster)) { target in
                    Text(Copy.targetTitle(target)).tag(target)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .background(OrangeTheme.canvas)
        .task { await load() }
    }

    private var preview: some View {
        Group {
            if let image = NSImage(contentsOf: file.url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .orangeCard(radius: 18)
    }

    private var parsedSize: (width: Int, height: Int)? {
        guard let width = Int(widthText), let height = Int(heightText), width > 0, height > 0, width < 20000, height < 20000 else {
            return nil
        }
        return (width, height)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OrangeTheme.muted)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var widthBinding: Binding<String> {
        Binding(
            get: { widthText },
            set: { newValue in
                widthText = newValue
                guard lockAspect, pixelSize.width > 0, pixelSize.height > 0, let width = Double(newValue) else { return }
                let next = Int((width * pixelSize.height / pixelSize.width).rounded())
                heightText = String(max(next, 1))
            }
        )
    }

    private var heightBinding: Binding<String> {
        Binding(
            get: { heightText },
            set: { newValue in
                heightText = newValue
                guard lockAspect, pixelSize.width > 0, pixelSize.height > 0, let height = Double(newValue) else { return }
                let next = Int((height * pixelSize.width / pixelSize.height).rounded())
                widthText = String(max(next, 1))
            }
        )
    }

    private func load() async {
        let url = file.url
        let size = await Task.detached {
            (try? ImageTranscoder().loadOriented(url)).map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        }.value
        pixelSize = size
        widthText = String(Int(size.width))
        heightText = String(Int(size.height))
        format = rasterFormat(file)
    }
}

private struct CropSheet: View {
    var file: FileRef
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var pixelSize: CGSize = .zero
    @State private var image: NSImage?
    @State private var selection: CGRect?
    @State private var origin: CGPoint?
    @State private var format: ConvertTarget = .jpeg
    @State private var viewSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(
                title: Copy.toolTitle(.crop),
                subtitle: file.name,
                saveTitle: Copy.saveCopy,
                canSave: normalized.width > 0.01 && normalized.height > 0.01
            ) {
                runtime.exportImage(
                    file,
                    operation: .cropNormalized(normalized),
                    format: format,
                    quality: runtime.jpegQuality
                )
                dismiss()
            }
            Text(Copy.cropHint)
                .font(.system(size: 12))
                .foregroundStyle(OrangeTheme.muted)
            GeometryReader { geo in
                ZStack {
                    OrangeTheme.card
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    if let selection {
                        Rectangle()
                            .fill(OrangeTheme.accent.opacity(0.18))
                            .overlay(Rectangle().strokeBorder(OrangeTheme.accent, lineWidth: 1.5))
                            .frame(width: selection.width, height: selection.height)
                            .position(x: selection.midX, y: selection.midY)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            viewSize = geo.size
                            let start = origin ?? value.startLocation
                            origin = start
                            var rect = CGRect(
                                x: min(start.x, value.location.x),
                                y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x),
                                height: abs(value.location.y - start.y)
                            )
                            if NSEvent.modifierFlags.contains(.shift) {
                                let side = max(rect.width, rect.height)
                                rect.size = CGSize(width: side, height: side)
                                if value.location.x < start.x { rect.origin.x = start.x - side }
                                if value.location.y < start.y { rect.origin.y = start.y - side }
                            }
                            selection = rect
                        }
                        .onEnded { _ in
                            origin = nil
                            viewSize = geo.size
                        }
                )
                .onAppear { viewSize = geo.size }
            }
            .frame(height: 360)
            Picker(Copy.format, selection: $format) {
                ForEach(ConvertTarget.allCases.filter(\.isRaster)) { target in
                    Text(Copy.targetTitle(target)).tag(target)
                }
            }
        }
        .padding(24)
        .frame(width: 720, height: 620)
        .background(OrangeTheme.canvas)
        .task {
            let url = file.url
            image = NSImage(contentsOf: url)
            pixelSize = await Task.detached {
                (try? ImageTranscoder().loadOriented(url)).map { CGSize(width: $0.width, height: $0.height) } ?? .zero
            }.value
            format = rasterFormat(file)
        }
    }

    private var normalized: CGRect {
        guard let selection, pixelSize.width > 0, viewSize.width > 0 else { return .zero }
        return CropMath.normalizedRect(selection: selection, imageSize: pixelSize, viewSize: viewSize)
    }
}

private struct RotateSheet: View {
    var file: FileRef
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var degrees = 0
    @State private var flipped = false
    @State private var format: ConvertTarget = .jpeg

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(
                title: Copy.toolTitle(.rotate),
                subtitle: file.name,
                saveTitle: Copy.saveCopy,
                canSave: degrees != 0 || flipped
            ) {
                runtime.exportTurn(file, degrees: degrees, flipped: flipped, format: format)
                dismiss()
            }
            Group {
                if let image = NSImage(contentsOf: file.url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(Double(degrees)))
                        .scaleEffect(x: flipped ? -1 : 1, y: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .orangeCard(radius: 18)
            HStack(spacing: 10) {
                Button(Copy.rotateLeft) { degrees = (degrees + 270) % 360 }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
                Button(Copy.rotateRight) { degrees = (degrees + 90) % 360 }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
                Button(Copy.straight) { degrees = (degrees + 180) % 360 }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
                Button(Copy.flip) { flipped.toggle() }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
            }
            Picker(Copy.format, selection: $format) {
                ForEach(ConvertTarget.allCases.filter(\.isRaster)) { target in
                    Text(Copy.targetTitle(target)).tag(target)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .background(OrangeTheme.canvas)
        .onAppear { format = rasterFormat(file) }
    }
}

private struct SplitSheet: View {
    var file: FileRef
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var pages = 0
    @State private var selection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(
                title: Copy.toolTitle(.splitPDF),
                subtitle: file.name,
                saveTitle: Copy.saveCopy,
                canSave: pages > 0 && (try? PDFToolkit.parsePageSelection(selection.isEmpty ? "all" : selection, pageCount: pages)) != nil
            ) {
                runtime.splitPDF(file, selection: selection.isEmpty ? "all" : selection)
                dismiss()
            }
            Text("\(Copy.pages): \(pages)")
                .font(.system(size: 13, weight: .medium))
            TextField(Copy.pageHint, text: $selection)
                .textFieldStyle(.roundedBorder)
            Text(Copy.pageHint)
                .font(.system(size: 12))
                .foregroundStyle(OrangeTheme.muted)
            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 280)
        .background(OrangeTheme.canvas)
        .task {
            let url = file.url
            pages = await Task.detached { (try? PDFToolkit.pageCount(of: url)) ?? 0 }.value
        }
    }
}

private func rasterFormat(_ file: FileRef) -> ConvertTarget {
    switch file.url.pathExtension.lowercased() {
    case "jpg", "jpeg": .jpeg
    case "png": .png
    case "webp": .webp
    case "heic", "heif": .heic
    case "tif", "tiff": .tiff
    case "bmp": .bmp
    case "gif": .gif
    default: .jpeg
    }
}
