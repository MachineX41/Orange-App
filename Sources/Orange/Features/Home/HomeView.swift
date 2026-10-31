import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !runtime.globalMonitorAvailable {
                    Text(Copy.monitorOff)
                        .font(.system(size: 12.5))
                        .foregroundStyle(OrangeTheme.ink)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .orangeCard(radius: 16)
                }
                dropWell
                if !runtime.selection.isEmpty {
                    selectionBar
                }
                legend
                if !runtime.shelf.isEmpty {
                    shelf
                }
                if !runtime.recentOutputs.isEmpty {
                    recent
                }
            }
            .padding(36)
            .padding(.top, 12)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(homeGlow)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ORANGE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(OrangeTheme.accent)
            Text(Copy.headlineLead)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(OrangeTheme.ink)
            Text(Copy.headlineAccent)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(OrangeTheme.accent)
            Text(Copy.subhead)
                .font(.system(size: 15))
                .foregroundStyle(OrangeTheme.muted)
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private var dropWell: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(OrangeTheme.accent.opacity(targeted ? 0.9 : 0.35), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(OrangeTheme.accent)
                    .frame(width: 10, height: 10)
            }
            Text(targeted ? Copy.dropActive : Copy.dropTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OrangeTheme.ink)
            Text(Copy.dropDetail)
                .font(.system(size: 13))
                .foregroundStyle(OrangeTheme.muted)
            HStack(spacing: 10) {
                Button(Copy.openFiles) { runtime.importerPresented = true }
                    .buttonStyle(OrangeButtonStyle(prominent: true))
                Button(Copy.sample) { runtime.useSample() }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .orangeCard(radius: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    targeted ? OrangeTheme.accent : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift) || flags.contains(.command) || flags.contains(.control) {
                return false
            }
            let providers = providers
            Task {
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { object, _ in
                            continuation.resume(returning: object)
                        }
                    }
                    if let url { urls.append(url) }
                }
                await MainActor.run {
                    runtime.importURLs(urls)
                }
            }
            return true
        }
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Copy.selection)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OrangeTheme.muted)
                Spacer()
                Button(Copy.clear) { runtime.selection = [] }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrangeTheme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(runtime.selection.prefix(10)) { file in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name)
                                    .lineLimit(1)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(OrangeTheme.bytes(file.byteCount))
                                    .font(.system(size: 10))
                                    .foregroundStyle(OrangeTheme.muted)
                            }
                            Button {
                                runtime.removeFromSelection(file)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(OrangeTheme.muted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(OrangeTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            HStack(spacing: 10) {
                Button(Copy.convert) { runtime.presentLocalWheel(.convert) }
                    .buttonStyle(OrangeButtonStyle(prominent: true))
                Button(Copy.tools) { runtime.presentLocalWheel(.tools) }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
                Button(Copy.actions) { runtime.presentLocalWheel(.actions) }
                    .buttonStyle(OrangeButtonStyle(prominent: false))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendCard(Copy.legendShift, Copy.legendConvert)
            legendCard(Copy.legendCommand, Copy.legendTools)
            legendCard(Copy.legendControl, Copy.legendActions)
        }
    }

    private func legendCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(OrangeTheme.ink)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(OrangeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .orangeCard(radius: 18)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Copy.shelf)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Copy.shelfHint)
                    .font(.system(size: 12))
                    .foregroundStyle(OrangeTheme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(runtime.shelf) { file in
                        Button {
                            runtime.selection = [file]
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                Text(file.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                            }
                            .padding(12)
                            .orangeCard(radius: 16)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(Copy.remove) { runtime.removeFromShelf(file) }
                            Button(Copy.reveal) {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                        }
                    }
                }
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.recent)
                .font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(runtime.recentOutputs) { file in
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineLimit(1)
                                Text(OrangeTheme.bytes(file.byteCount))
                                    .font(.system(size: 11))
                                    .foregroundStyle(OrangeTheme.muted)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .orangeCard(radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var homeGlow: some View {
        ZStack {
            OrangeTheme.canvas
            Circle()
                .fill(OrangeTheme.accent.opacity(0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: 280, y: -220)
        }
        .ignoresSafeArea()
    }
}

struct OrangeButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : OrangeTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(OrangeTheme.accent) : AnyShapeStyle(OrangeTheme.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : OrangeTheme.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
