import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Ayarlar → Oynatıcı bölümü.
///
/// ⚠️ Buradaki her satır **gerçekten bir davranışı değiştirir**; süs ayar
/// yok. Karşılıkları: tampon → `PlaybackPreferences.LiveBuffer` (motorların
/// `load()` anında okuduğu değer), yerleşim → `PlayerController.videoFit`,
/// yeniden bağlanma → `PlayerController.reconnectIfLive`, yedek motor →
/// `PlayerController.handleFailure`.
extension SettingsScreen {

    var playbackSection: some View {
        section("Oynatıcı") {
            liveBufferPicker
            videoFitPicker
            autoReconnectToggle
            fallbackEngineToggle
        }
    }

    /// Kanal geçiş hızını doğrudan belirleyen ayar.
    private var liveBufferPicker: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.md) {
                    rowLabel(icon: "timer", title: "Canlı yayın tamponu")
                    Spacer(minLength: Theme.Spacing.sm)

                    Picker("", selection: $playback.liveBuffer) {
                        ForEach(PlaybackPreferences.LiveBuffer.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text(playback.liveBuffer.detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
    }

    private var videoFitPicker: some View {
        settingsCard {
            HStack(spacing: Theme.Spacing.md) {
                rowLabel(
                    icon: "rectangle.arrowtriangle.2.inward",
                    title: "Görüntü yerleşimi"
                )
                Spacer(minLength: Theme.Spacing.sm)

                Picker("", selection: $playback.videoFit) {
                    Text("Ekrana sığdır").tag(VideoFit.fit)
                    Text("Ekranı doldur").tag(VideoFit.fill)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var autoReconnectToggle: some View {
        settingsCard {
            Toggle(isOn: $playback.autoReconnect) {
                VStack(alignment: .leading, spacing: 2) {
                    rowLabel(icon: "arrow.clockwise", title: "Kopunca yeniden bağlan")
                    Text("Canlı yayın kesilirse sessizce tekrar denenir")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                }
            }
            .tint(Theme.Palette.accent)
        }
    }

    private var fallbackEngineToggle: some View {
        settingsCard {
            Toggle(isOn: $playback.useFallbackEngine) {
                VStack(alignment: .leading, spacing: 2) {
                    rowLabel(icon: "shippingbox", title: "Yedek oynatıcı")
                    // ⚠️ Kapatmanın bedeli açıkça yazılıyor: kullanıcı
                    // "neden kanallarım açılmıyor" diye dönmesin.
                    Text("Kapatılırsa bazı UHD/HEVC kanallar açılmaz")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                }
            }
            .tint(Theme.Palette.accent)
        }
    }

    // MARK: - Ortak parçalar

    private func rowLabel(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(Theme.Palette.accent)
                .frame(width: 24)
            Text(title)
                .font(Theme.Typography.rowTitle)
                .foregroundColor(Theme.Palette.textPrimary)
        }
    }

    /// Bölümdeki satırların ortak kabı — `startupSection`'daki seçiciyle
    /// aynı görünüm, tekrar yazmamak için burada.
    /// ⚠️ Etiketler Picker'a **bırakılmıyor**, elle çiziliyor: `.menu`
    /// stilindeki bir Picker `Form`/`List` dışında yalnızca seçili değeri
    /// gösteriyor, `label:` içeriğini hiç çizmiyor. Ekranda "Dengeli"
    /// yazıyordu ama neyin dengeli olduğu yazmıyordu.
    /// `maxWidth: .infinity` de kartlar eşit genişlikte dursun diye.
    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
