# AmllyEdit Pad

HarmonyOS 4.x / Android tabletler için, kalem ve harici klavye uyumlu profesyonel video kurgu uygulaması (Flutter + yerel Android medya katmanı).

## İndirme
En güncel APK: **Releases** bölümündeki son sürüm (`AmllyEditPad-vX.Y.Z.apk`).

## Yapı
- `lib/`: Flutter arayüzü ve uygulama mantığı
  - `app/`: tema, sürüm, başlangıç
  - `core/`: biçimlendirme ve yerel medya köprüsü (`amlly/media` kanalı)
  - `models/`, `services/`, `state/`: proje modeli, güvenli kayıt, çalışma alanı durumu
  - `ui/`: paneller ve ortak bileşenler
- `android/app/src/main/`: manifest ve Kotlin medya katmanı (seçici, analiz, küçük resim). Android Gradle iskeleti derlemede `flutter create` ile, sabitlenmiş Flutter sürümünden üretilir.
- `android/imza/`: parola korumalı imza anahtarı. Parola yalnızca GitHub gizli değişkeninde (`AMLLY_IMZA_PAROLA`) tutulur.
- `arsiv/`: önceki yapay zekâ sürümünün dosyaları (kullanılmıyor, başvuru için saklanıyor).

## Derleme
`main` dalına her gönderimde GitHub Actions şu adımları çalıştırır: analiz, testler, arm64 APK, sabit anahtarla imza, Release güncellemesi. Derleme raporu `ci-rapor` dalına yazılır.

## Yol haritası
- v0.1: Temel, medya havuzu, paneller, otomatik kayıt ✔
- v0.2: Oynatma, zaman çizelgesine yerleştirme
- v0.3: Kesme, bölme, taşıma, geri al / yinele
- v0.4: Dışa aktarma (H.264, 1080p)
- v0.5+: Ses, metin, geçişler, anahtar kareler
- v0.6: Supabase bulut yedekleme (yalnızca proje kaydı)
