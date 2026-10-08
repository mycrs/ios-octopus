import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusPlayback

struct SourceHealthScreen: View {
    @StateObject private var viewModel: SourceHealthViewModel
    @EnvironmentObject private var language: LanguageController

    init(dependencies: SettingsDependencies) {
        _viewModel = StateObject(wrappedValue: SourceHealthViewModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Bu kontrol cihazdaki katalog bilgilerini inceler. Yayın erişimini veya codec uyumluluğunu ölçmez.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let error = viewModel.error {
                    InlineMessageView(text: language.localized(error), kind: .info)
                } else if let summary = viewModel.snapshot {
                    catalog(summary)
                    if let playback = viewModel.playback { player(playback) }
                    if let report = viewModel.shareText {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ShareLink(item: report) {
                                Label("Destek raporunu paylaş", systemImage: "square.and.arrow.up")
                            }
                            Text("Rapor içerik adlarını, kaynak adresini, kullanıcı adını, parolayı veya PIN'i içermez.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Palette.textSecondary)
                        }
                        .settingsSurface()
                    }
                } else {
                    Text("Kontrol için önce bir kaynak ekle ve etkinleştir.")
                        .foregroundColor(Theme.Palette.textSecondary)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle("Kaynak kontrolü")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Yenile") { Task { await viewModel.load() } }
                    .disabled(viewModel.isLoading)
            }
        }
        .task { await viewModel.load() }
    }

    private func catalog(_ summary: SourceHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Yerel katalog").font(Theme.Typography.sectionTitle)
                .accessibilityIdentifier("source-health.catalog")
            row("Kaynak türü", value: language.localized(sourceTitle(summary.sourceKind)))
            row("Canlı TV", value: "\(summary.channels)")
            row("Filmler", value: "\(summary.movies)")
            row("Diziler", value: "\(summary.series)")
            row("Kategoriler", value: "\(summary.categories)")
            if let date = summary.lastSyncedAt {
                row("Son güncelleme", value: date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(language.locale)))
            } else {
                Text("Henüz güncellenmedi").font(Theme.Typography.caption)
            }
            if summary.accountExpired {
                Text("Kaynak aboneliğinin süresi dolmuş görünüyor.")
                    .foregroundColor(Theme.Palette.warning)
            }
            Divider()
            row("Tekrarlanan yayın kaydı", value: "\(summary.duplicateChannels)")
            row("Rehber kimliği eksik", value: "\(summary.channelsWithoutGuide)")
            row("Logosu eksik", value: "\(summary.channelsWithoutArtwork)")
            Text("Tekrarlar kaynakta bilinçli tanımlanmış olabilir. Eksik rehber veya logo bilgisi yayının çalışmadığı anlamına gelmez.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textSecondary)
        }
        .settingsSurface()
    }

    private func player(_ snapshot: PlaybackDiagnosticSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Oynatıcı anlık durumu").font(Theme.Typography.sectionTitle)
            row("Durum", value: language.localized(stateTitle(snapshot.state)))
            if let engine = snapshot.engine {
                row("Oynatıcı", value: engine == .native ? "AVPlayer" : "VLC")
            }
            if let format = snapshot.format { row("Yayın biçimi", value: format.rawValue) }
            row("Ses izi", value: "\(snapshot.audioTrackCount)")
            row("Altyazı izi", value: "\(snapshot.subtitleTrackCount)")
            if let ready = snapshot.firstVideoFrameReady {
                row("İlk görüntü karesi", value: language.localized(ready ? "Hazır" : "Henüz hazır değil"))
            }
        }
        .settingsSurface()
    }

    private func row(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(language.localized(title))
                Spacer(minLength: Theme.Spacing.md)
                Text(value).foregroundColor(Theme.Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(language.localized(title))
                Text(value).foregroundColor(Theme.Palette.textSecondary)
            }
        }
        .font(Theme.Typography.rowSubtitle)
    }

    private func sourceTitle(_ kind: SourceHealthSnapshot.SourceKind) -> String {
        switch kind {
        case .xtream: return "Xtream hesabı"
        case .m3u: return "M3U listesi"
        case .localFile: return "Yerel M3U dosyası"
        case .activation: return "Aktivasyon kaynağı"
        case .sampleLibrary: return "Örnek kütüphane"
        }
    }

    private func stateTitle(_ state: PlaybackDiagnosticSnapshot.State) -> String {
        switch state {
        case .idle: return "Oynatma yok"
        case .loading: return "Yükleniyor"
        case .buffering: return "Tamponlanıyor"
        case .playing: return "Oynatılıyor"
        case .paused: return "Duraklatıldı"
        case .ended: return "Tamamlandı"
        case .failed: return "Oynatma başarısız"
        }
    }
}
