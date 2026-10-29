# Şehir Simülasyonu — Faz 1 (Temel)

Godot 4.7.2 (Mobile renderer, Vulkan) ile Android için şehir kurma simülasyonu.
Mimari Cities: Skylines 2'den ilham alır; bu klasör **Faz 1**'i içerir.

## Faz 1'de ne var

| Parça | Dosya | Ne yapar |
|---|---|---|
| Veri servisi | `scripts/systems/game_data.gd`, `scripts/data/data_loader.gd` | `data/*.json` dosyalarını okur. Kodda dengeleme sayısı yok, hepsi JSON'da. |
| Olay yolu | `scripts/systems/event_bus.gd` | Sistemler birbirini tanımaz, sinyallerle konuşur. |
| Zaman | `scripts/data/sim_clock.gd`, `scripts/systems/time_system.gd` | Sabit 10 Hz tick, Dur/1x/2x/3x. 1 oyun günü = 1 ay. Render'dan bağımsız. |
| Dokunmatik | `scripts/data/gesture_tracker.gd`, `scripts/systems/input_controller.gd` | Kaydırma, sıkıştırma ile zoom, döndürme, iki parmakla eğim, dokunma, uzun basma, savurma (fling). |
| Kamera | `scripts/systems/camera_controller.gd` | Harita görünümünden sokak seviyesine yumuşak geçiş; eğim zoom'a bağlı, sınırlı. |
| Arazi | `scripts/systems/terrain_system.gd`, `assets/materials/terrain.gdshader` | 4 km × 4 km oynanabilir düz arazi + kilitli çevre, 8 m imar ızgarası (açılıp kapanır). |
| Gün-gece | `scripts/world/day_night_cycle.gd` | Güneş/ay yönü, renk sıcaklığı (Kelvin), gökyüzü, sis, pozlama, global `night_factor`. |
| Grafik kalitesi | `scripts/systems/graphics_settings.gd` | Düşük / Orta / Yüksek ön ayarlar (`data/graphics.json`). Seçim kaydedilir. |
| Arayüz | `scripts/ui/hud.gd` | Üst çubuk (tarih, saat, hız, FPS), alt araç çubuğu, ayarlar, konum bilgisi, bildirim. |
| Referans sahne (geçici) | `scripts/world/reference_scene.gd` + `assets/materials/*.gdshader` | Işık, gölge ve ölçeği telefonda değerlendirmek için bina blokları ve ağaçlar. Faz 2-3'te kalkacak. |
| Testler | `tests/run_tests.gd` | Görselsiz (headless) birim testleri: saat, hız, ay geçişi, jestler, ızgara. |

## Kontroller

**Telefon:** tek parmakla sürükle = kaydır · iki parmakla sıkıştır = zoom · iki parmakla döndür = kamerayı çevir ·
iki parmakla yukarı/aşağı kaydır = eğim · uzun bas = konum bilgisi · geri tuşu = paneli kapat / iki kez basınca çık.

**Masaüstü (editörde test):** sol sürükle = kaydır · sağ sürükle = döndür + eğim · tekerlek = zoom · sol basılı tut = konum bilgisi.

## Kabul kriterleri ve test

| # | Kriter | Nasıl test edilir |
|---|---|---|
| 1 | Proje hatasız açılır ve çalışır | Godot 4.7.2'de `citysim/project.godot` aç, F5. Çıktı panelinde hata olmamalı. |
| 2 | Birim testleri geçer | `godot --headless --path citysim -s res://tests/run_tests.gd` → `31 checks, 0 failed` |
| 3 | Kamera tüm jestlere tepki verir, harita dışına çıkmaz | Kaydır, zoom yap, döndür, eğ. Odak noktası açık renkli sınır çizgisinin (4 km) dışına çıkmamalı. |
| 4 | Zoom ile eğim yumuşakça değişir | En yakına zoom yap: kamera sokak seviyesine iner; en uzağa: harita görünümü. |
| 5 | Gün-gece döngüsü çalışır | Ayarlar → "Günün saati" kaydırıcısı. Sabah/akşam ışığı sıcak, öğlen nötr, gece pencereler rastgele yanar. |
| 6 | Hız düğmeleri çalışır | Dur → saat durur. 3x → saat 1x'in üç katı hızda ilerler. Gün bitince ay değişir. |
| 7 | Butona dokunmak kamerayı oynatmaz | Alt çubuktaki bir araca dokun → sadece bildirim çıkar, harita kaymaz. |
| 8 | Kalite ayarları uygulanır | Ayarlar → Düşük/Orta/Yüksek. Gölge ve görüntü keskinliği değişir, uygulama yeniden açıldığında seçim hatırlanır. |
| 9 | Uzun basma bilgi verir | Zemine uzun bas → konum (m), hücre (8 m) ve "oynanabilir alan / kilitli" bilgisi. |
| 10 | APK telefonda açılır, yatay ekran, Türkçe arayüz | Aşağıdaki adımlarla kur. FPS sağ üstte görünür; orta segment cihazda 30+ FPS hedeflenir. |

## APK nasıl alınır

### Yol A — Otomatik (önerilen, hiçbir şey kurmadan)
Bu repoda `.github/workflows/citysim-android.yml` var. `citysim/` içinde bir değişiklik push edildiğinde GitHub:
1. Godot 4.7.2 ve Android export şablonlarını indirir,
2. Testleri çalıştırır,
3. arm64-v8a **debug imzalı** APK üretir,
4. APK'yı hem Actions "Artifacts" bölümüne hem de **Releases → `citysim-latest`** sürümüne koyar.

Telefondan: repo sayfası → Releases → `citysim-latest` → `SehirSim.apk` indir → "Bilinmeyen kaynaklardan yükleme" iznini ver → kur.

### Yol B — Kendi bilgisayarında (Godot editörü)
1. **Godot 4.7.2** (standart sürüm, .NET değil) indir.
2. **JDK 17** kur (ör. Temurin 17).
3. **Android SDK** kur: Android Studio'nun SDK Manager'ından *Platform-Tools*, *Build-Tools 35+*, *Android SDK Platform 35+*.
   (Android Studio istemezsen *command-line tools* ile `sdkmanager "platform-tools" "build-tools;35.0.0" "platforms;android-35"`.)
4. Godot → Editor → Editor Settings → Export → Android:
   - *Java SDK Path* = JDK 17 klasörü
   - *Android SDK Path* = SDK klasörü
5. Godot → Editor → **Manage Export Templates** → *Download and Install*.
6. **Keystore:**
   - Debug: Godot ilk açılışta kendisi oluşturur, ek iş yok.
   - Release (Play Store / kalıcı imza) için bir kez üret ve **güvenli sakla** (kaybedersen güncelleme yayınlayamazsın):
     ```
     keytool -genkeypair -v -keystore sehirsim-release.keystore -alias sehirsim -keyalg RSA -keysize 2048 -validity 10000
     ```
     Sonra Project → Export → Android → *Keystore → Release* alanlarına yolu, alias'ı ve şifreyi gir.
     Keystore'u **asla** repoya koyma (`.gitignore` zaten engelliyor).
7. Project → Export → **Android** ön ayarı hazır (arm64-v8a, yatay, `data/*.json` dahil, `tests/` hariç) → *Export Project* → `SehirSim.apk`.
8. Telefona kur: USB ile `adb install -r SehirSim.apk` ya da dosyayı telefona atıp aç.

## Varsayımlar (kısaca)
- Godot sürümü: en güncel kararlı **4.7.2**.
- Proje, mevcut site reposunu bozmamak için `citysim/` alt klasöründe.
- Paket adı `io.github.hasanali6.sehirsim` (istersen değiştir, ama yayından sonra değiştirilemez).
- Güneş yolu basitleştirildi: enlem 41° (İstanbul civarı), mevsimsel sapma yok (mevsimler Faz 8).
- 1x hızda bir oyun günü (= 1 ay) 6 gerçek dakika (`data/time.json` → `real_seconds_per_day_at_1x`).
- Mobile renderer'da FSR yok (yalnızca Forward+), bu yüzden düşük ayarlarda bilinear ölçekleme kullanılıyor.

## Bilinen eksikler / sonraki fazlara kalanlar
- **Referans sahne geçicidir**: bina kutuları ve ağaçlar sadece ışık/ölçek testi için. `data/reference_scene.json` → `"enabled": false` ile kapanır. Faz 2 (yollar) ve Faz 3 (büyüyen binalar) bunun yerini alacak.
- Ağaçlar düşük poligonlu yer tutucu; gerçek ağaçlar için LOD + uzakta billboard (impostor) gerekecek — 1000'lerce ağaçta bu şart.
- Sokak lambaları, araçlar, yağmur/kar, mevsim renkleri yok (Faz 6, 8, 9).
- Su kütleleri ve arazi yüksekliği yok. Fazlar listesinde de yok — **Faz 2 veya 3'e eklemeyi öneririm**, çünkü yol ve imar sistemi suyu/eğimi bilmeli.
- Kayıt sistemi yok (Faz 8); sadece grafik ayarı `user://settings.cfg`'ye kaydediliyor.
- Listedeki diğer sistemler (RoadNetwork, ZoneSystem, …) ilgili fazlarda eklenecek; boş taslak dosya bırakılmadı.
- Gölge kalitesi kamera mesafesine göre otomatik ayarlanıyor; çok uzak harita görünümünde gölgeler yumuşar (bilinçli mobil tercih).
