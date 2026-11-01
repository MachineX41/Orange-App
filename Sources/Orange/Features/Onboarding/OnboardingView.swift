import OrangeKit
import SwiftUI

/// First-launch tour. Explains the wheel, asks for consent to the privacy notice and terms,
/// and lets the user grant folder access one by one. Nothing is requested without a click.
struct OnboardingView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var agreed = Consent.accepted
    var onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, wheel, privacy, permissions, ready
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .frame(width: StudioWindow.width, height: StudioWindow.height)
        .background(OrangeBackdrop())
        .interactiveDismissDisabled()
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome: WelcomePage()
        case .wheel: WheelPage()
        case .privacy: PrivacyPage(agreed: $agreed)
        case .permissions: PermissionsPage()
        case .ready: ReadyPage()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button(L("Back", "Geri")) { go(-1) }
                    .buttonStyle(.glass).tint(nil)
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? OrangeTheme.accent : Color.primary.opacity(0.16))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
            .accessibilityElement()
            .accessibilityLabel(L("Step \(step.rawValue + 1) of \(Step.allCases.count)", "Adım \(step.rawValue + 1) / \(Step.allCases.count)"))
            Spacer()
            Button(primaryTitle) { advance() }
                .buttonStyle(.glassProminent)
                .tint(OrangeTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(step == .privacy && !agreed)
                .help(step == .privacy && !agreed ? L("Accept the privacy notice and terms to continue.", "Devam etmek için gizlilik bildirimini ve koşulları kabul edin.") : "")
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: L("Get Started", "Başlayalım")
        case .privacy: L("Accept and Continue", "Kabul Et ve Devam Et")
        case .ready: L("Start Using Orange", "Orange’ı Kullanmaya Başla")
        default: L("Continue", "Devam")
        }
    }

    private func advance() {
        if step == .privacy {
            guard agreed else { return }
            Consent.accept()
        }
        if step == .ready {
            onFinish()
            return
        }
        go(1)
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.88)) {
            step = next
        }
    }
}

// MARK: Pages

private struct PageTitle: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomePage: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            OrangeMark(side: 96)
                .shadow(color: OrangeTheme.accent.opacity(0.25), radius: 18, y: 8)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
            PageTitle(
                title: L("Welcome to Orange", "Orange’a hoş geldiniz"),
                subtitle: L("Convert, edit and move files right where you drag them. Everything runs on your Mac.", "Dosyaları sürüklediğiniz yerde dönüştürün, düzenleyin ve taşıyın. Her şey Mac’inizde çalışır.")
            )
            HStack(spacing: 12) {
                feature("arrow.triangle.2.circlepath", L("Convert", "Dönüştür"), L("Images, video, audio, PDF and documents", "Görsel, video, ses, PDF ve belgeler"), delay: 0.1)
                feature("slider.horizontal.3", L("Edit", "Düzenle"), L("Crop, trim, compress, redact and more", "Kırp, kes, sıkıştır, gizle ve fazlası"), delay: 0.18)
                feature("tray.and.arrow.down", L("Move", "Taşı"), L("Shelf, AirDrop, zip and quick actions", "Raf, AirDrop, sıkıştırma ve hızlı eylemler"), delay: 0.26)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { appeared = true }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .glassCard(radius: 18)
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(delay), value: appeared)
    }
}

private struct WheelPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 22) {
            PageTitle(
                title: L("Drag, hold a key, drop", "Sürükle, tuşa bas, bırak"),
                subtitle: L("Start dragging a file anywhere, in Finder or any app. Hold a key and a wheel opens under the pointer. It stays put, so you just drop on a slice.", "Finder’da ya da herhangi bir uygulamada bir dosyayı sürüklemeye başlayın. Bir tuşa basılı tutun, imlecin altında bir çark açılır. Çark yerinde durur, dosyayı bir dilime bırakmanız yeterli.")
            )
            .padding(.top, 34)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let period = HowItWorks.period
                let progress = reduceMotion ? 0.6 : time.truncatingRemainder(dividingBy: period) / period
                let mode = WheelMode.allCases[reduceMotion ? 0 : Int(time / period) % WheelMode.allCases.count]
                HStack(spacing: 22) {
                    WheelDemo(mode: mode, progress: progress)
                        .frame(width: 250, height: 190)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(WheelMode.allCases, id: \.self) { item in
                            HStack(alignment: .top, spacing: 12) {
                                KeyCap(text: item.key, pressed: item == mode)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 13.5, weight: .semibold))
                                    Text(item.explanation)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .animation(.easeOut(duration: 0.2), value: mode)
                        }
                    }
                    .frame(width: 300, alignment: .leading)
                }
                .padding(18)
                .glassCard(radius: 22)
            }
            Text(L("Inside Orange, select files and press ⌘E, ⌘T or ⌘J for the same wheels. ⌘/ lists every shortcut.", "Orange içinde dosya seçip ⌘E, ⌘T ya da ⌘J ile aynı çarkları açabilirsiniz. ⌘/ tüm kısayolları gösterir."))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Spacer(minLength: 0)
        }
    }
}

private struct PrivacyPage: View {
    @Binding var agreed: Bool

    var body: some View {
        VStack(spacing: 18) {
            PageTitle(
                title: L("Private by design", "Gizlilik öncelikli"),
                subtitle: L("Please read how Orange treats your files before you start.", "Başlamadan önce Orange’ın dosyalarınızı nasıl ele aldığını okuyun.")
            )
            .padding(.top, 30)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    point("lock.laptopcomputer", L("On your Mac", "Mac’inizde"), L("Files are converted and edited locally. Nothing is uploaded to Orange or anyone else.", "Dosyalar yerelde dönüştürülür ve düzenlenir. Hiçbir şey Orange’a ya da başka birine yüklenmez."))
                    point("person.crop.circle.badge.xmark", L("No account, no tracking", "Hesap yok, takip yok"), L("No sign-up, analytics, advertising identifiers or crash reporting.", "Kayıt, analiz, reklam kimliği ya da çökme raporu yoktur."))
                    point("network", L("Network only when you ask", "Ağ yalnızca siz isteyince"), L("Orange connects to the internet only to download a link you paste, and only to that site.", "Orange internete yalnızca yapıştırdığınız linki indirmek için ve yalnızca o siteye bağlanır."))
                    point("internaldrive", L("History stays here", "Geçmiş burada kalır"), L("Your job history and shelf are stored in your user Library. Clear them any time in Library and Shelf.", "İş geçmişiniz ve rafınız kullanıcı Kitaplığınızda saklanır. Kitaplık ve Raf’tan istediğiniz an silebilirsiniz."))
                    point("exclamationmark.shield", L("Your responsibility for downloads", "İndirmelerde sorumluluk sizde"), L("Only download content you own or have permission to save. Respect copyright and each site’s terms. Link downloads for most sites use yt-dlp, a separate open-source tool you install yourself.", "Yalnızca size ait ya da kaydetme izniniz olan içerikleri indirin. Telif haklarına ve sitelerin kullanım koşullarına uyun. Çoğu sitede link indirme, kendiniz kurduğunuz ayrı ve açık kaynaklı yt-dlp aracını kullanır."))
                    point("doc.badge.gearshape", L("Results are new copies", "Sonuçlar yeni kopyadır"), L("Originals are never overwritten. Orange is provided as is; keep backups of important files.", "Orijinaller hiçbir zaman üzerine yazılmaz. Orange olduğu gibi sunulur; önemli dosyalarınızı yedekleyin."))
                }
                .padding(18)
            }
            .frame(width: 600, height: 250)
            .glassCard(radius: 20)

            VStack(spacing: 8) {
                Toggle(isOn: $agreed.animation(.easeOut(duration: 0.15))) {
                    Text(L("I have read and accept the Privacy Notice and Terms of Use.", "Gizlilik Bildirimi’ni ve Kullanım Koşulları’nı okudum, kabul ediyorum."))
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.checkbox)
                HStack(spacing: 14) {
                    Link(L("Privacy Notice", "Gizlilik Bildirimi"), destination: Consent.privacyURL)
                    Link(L("Terms of Use", "Kullanım Koşulları"), destination: Consent.termsURL)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OrangeTheme.accent)
            }
            Spacer(minLength: 0)
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionsPage: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var permissions = Permissions.shared

    var body: some View {
        @Bindable var runtime = runtime
        VStack(spacing: 18) {
            PageTitle(
                title: L("Permissions, on your terms", "İzinler sizin kontrolünüzde"),
                subtitle: L("macOS asks before any app reads Desktop, Documents or Downloads. Grant the folders you use, now or later. You can change this in System Settings any time.", "macOS, bir uygulama Masaüstü, Belgeler ya da İndirilenler’e erişmeden önce size sorar. Kullandığınız klasörlere şimdi ya da sonra izin verin. Bunu her zaman Sistem Ayarları’ndan değiştirebilirsiniz.")
            )
            .padding(.top, 30)

            VStack(spacing: 0) {
                ForEach(ProtectedFolder.allCases) { folder in
                    FolderRow(folder: folder)
                    if folder != ProtectedFolder.allCases.last { Divider().padding(.leading, 52) }
                }
            }
            .padding(.vertical, 6)
            .frame(width: 600)
            .glassCard(radius: 20)

            VStack(spacing: 0) {
                switchRow(
                    "power",
                    L("Open at login", "Girişte aç"),
                    L("Keeps the drag wheel ready after a restart. Off by default.", "Yeniden başlatmadan sonra sürükleme çarkını hazır tutar. Varsayılan olarak kapalı."),
                    isOn: Binding(get: { permissions.opensAtLogin }, set: { permissions.setOpensAtLogin($0) })
                )
                Divider().padding(.leading, 52)
                switchRow(
                    "menubar.rectangle",
                    L("Show in menu bar", "Menü çubuğunda göster"),
                    L("Quick access to files, shelf and recent results.", "Dosyalara, rafa ve son sonuçlara hızlı erişim."),
                    isOn: $runtime.showInMenuBar
                )
            }
            .frame(width: 600)
            .glassCard(radius: 20)

            if let error = permissions.loginItemError {
                Text(error).font(.system(size: 11.5)).foregroundStyle(OrangeTheme.ember)
            }
            Text(L("Orange never asks for Accessibility, Screen Recording, Camera, Microphone, Contacts or Location.", "Orange hiçbir zaman Erişilebilirlik, Ekran Kaydı, Kamera, Mikrofon, Kişiler ya da Konum izni istemez."))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .onAppear { permissions.refreshLoginItem() }
    }

    private func switchRow(_ symbol: String, _ title: String, _ text: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One protected folder with its state and a button that triggers the system prompt.
struct FolderRow: View {
    var folder: ProtectedFolder
    @State private var permissions = Permissions.shared

    var body: some View {
        let state = permissions.access(folder)
        HStack(spacing: 12) {
            Image(systemName: folder.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.title).font(.system(size: 13, weight: .semibold))
                Text(folder.reason).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            Group {
                if permissions.checking.contains(folder) {
                    ProgressView().controlSize(.small)
                } else {
                    switch state {
                    case .granted:
                        Label(L("Allowed", "İzin verildi"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12, weight: .medium))
                    case .denied:
                        Button(L("Open Settings", "Ayarları Aç")) { permissions.openPrivacySettings() }
                            .buttonStyle(.glass).tint(nil)
                            .help(L("Access was declined. Turn it on under Privacy & Security › Files & Folders.", "Erişim reddedildi. Gizlilik ve Güvenlik › Dosyalar ve Klasörler’den açabilirsiniz."))
                    case .unknown:
                        Button(L("Allow…", "İzin Ver…")) { permissions.request(folder) }
                            .buttonStyle(.glass).tint(nil)
                    }
                }
            }
            .controlSize(.regular)
            .animation(.easeOut(duration: 0.2), value: state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

private struct ReadyPage: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.white, OrangeTheme.accent)
                .symbolEffect(.bounce, value: appeared)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            PageTitle(
                title: L("You’re all set", "Her şey hazır"),
                subtitle: L("A few shortcuts to remember. You can replay this tour from the Help menu.", "Akılda tutulacak birkaç kısayol. Bu tanıtımı Yardım menüsünden yeniden izleyebilirsiniz.")
            )
            VStack(spacing: 10) {
                row(["⇧", "⌘", "⌃"], L("While dragging: Convert, Tools, Actions", "Sürüklerken: Dönüştür, Araçlar, Eylemler"))
                row(["⌘", "O"], L("Open files", "Dosya aç"))
                row(["⌘", "E"], L("Wheel for the selection", "Seçim için çark"))
                row(["⌘", "/"], L("All keyboard shortcuts", "Tüm klavye kısayolları"))
            }
            .padding(18)
            .frame(width: 440)
            .glassCard(radius: 20)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
    }

    private func row(_ keys: [String], _ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            KeyCombo(keys: keys)
        }
    }
}
