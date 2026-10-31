# Şehir Simülasyonu — Faz 1 (Temel) + Faz 2 (Yollar)

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
| Grafik kalitesi | `scripts/systems/graphics_settings.gd` | Düşük / Orta / Yüksek ön ayarlar (`data/graphics.json`). Seçim kaydedilir. Dinamik çözünürlük ölçülen GPU süresine bakar; 90/144 Hz ekranlarda FPS kilidi kaldırılır (aksi halde 45/72'ye takılır). |
| Arayüz | `scripts/ui/hud.gd`, `scripts/ui/ui_style.gd` | Mobil şehir oyunu düzeni: sol üstte nüfus/mutluluk, ortada saat ve hız, sağ üstte para ve ayarlar, sağ altta büyük **İnşa Et** düğmesi ve kategori menüsü. İkonlar Lucide (ISC), font Nunito (OFL); lisanslar `assets/ui/` içinde. |
| Referans sahne (kapalı) | `scripts/world/reference_scene.gd` + `assets/materials/*.gdshader` | Işık testi için bina blokları ve ağaçlar. Varsayılan **kapalı** — harita boş başlar. `data/reference_scene.json` → `"enabled": true` ile açılır. |
| Testler | `tests/run_tests.gd` | Görselsiz (headless) birim testleri: saat, hız, ay geçişi, jestler, ızgara. |

## Faz 2: Yollar

| Parça | Dosya | Ne yapar |
|---|---|---|
| Yol grafı | `scripts/data/road_graph.gd` | Kavşak (node) + yol parçası (ikinci dereceden Bezier). Önce `plan_road` ile doğrular (kısa/uzun, var olan yol, dar açı, çok yakın kavşak), sonra `commit_road` ile kesiştiği yolları böler; her kesişme otomatik kavşak olur. Görselsiz, test edilebilir. |
| Yol tipleri ve şeritler | `scripts/data/road_types.gd`, `data/roads.json` | Sokak 8 m, cadde 16 m, bulvar 24 m (refüjlü), tek yön sokak/cadde. Şeritler sağdan akar; Faz 6 trafiği bunları kullanacak. |
| Yol görseli | `scripts/world/road_mesh_builder.gd`, `assets/materials/road_*.gdshader` | Asfalt, şerit çizgileri, sarı orta çizgi, yaya geçidi, yükseltilmiş kaldırım, bordür, yuvarlak kavşak köşeleri. Tüm yol tipleri ve kavşaklar tek asfalt shader'ı kullanır. |
| Yol sistemi | `scripts/systems/road_network.gd` | Parçalar 256 m'lik bölgelerde tek mesh'e birleşir (az çizim çağrısı). Düzenleme sadece etrafını yeniden üretir. Sokak lambaları ve gece ışık havuzları MultiMesh. |
| Yol aracı | `scripts/world/road_tool.gd` | Düz / eğri / yık. Kavşağa, yola, 15° açıya + 8 m uzunluğa ve 8 m ızgaraya yapışır. Yeşil/kırmızı önizleme ve parmağın üstünde maliyet. |
| Bütçe (başlangıç) | `scripts/systems/economy_system.gd`, `data/economy.json` | 50.000 başlangıç parası; yol yapınca düşer, yıkınca %75'i geri gelir. Vergi/bütçe Faz 4. |

**Yol çizme:** İnşa Et → Yollar → tip ve mod seç.
- **Düz:** parmağı bas, sürükle, bırak.
- **Eğri:** önce başlangıçtan kıvrım noktasına çiz, bırak; sonra bitişi sürükle, bırak.
- **Yık:** yola dokun, bırak.

Araç açıkken tek parmak çizer, iki parmak kamerayı oynatır (kaydır, yakınlaştır, döndür).

**Faz 2 kabul kriterleri:** kesişen iki yol kavşak oluşturur · bir yolun ortasına bitirilen yol T kavşağı yapar · var olan yolun ucuna yapışır · üst üste/çok dar açılı/çok kısa yol kırmızı önizleme ve uyarı verir · para yoksa yapılmaz · yıkınca para iade edilir ve kavşak düzelir · eğri yol pürüzsüz çizilir · gece lambalar yanar. Otomatik testler: `65 checks, 0 failed`.

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
| 7 | Butona dokunmak kamerayı oynatmaz | İnşa Et → bir kategoriye dokun → sadece bildirim çıkar, harita kaymaz. |
| 8 | Kalite ayarları uygulanır | Ayarlar → Düşük/Orta/Yüksek. Gölge ve görüntü keskinliği değişir, uygulama yeniden açıldığında seçim hatırlanır. |
| 9 | Uzun basma bilgi verir | Zemine uzun bas → konum (m), hücre (8 m) ve "oynanabilir alan / kilitli" bilgisi. |
| 10 | APK telefonda açılır, yatay ekran, Türkçe arayüz, akıcı | Sol altta `FPS 60 · GPU 9.8 ms · CPU 3.1 ms · 120 Hz · 3D 75%` gibi bir satır var. GPU 14 ms'yi aşarsa 3D yüzdesi kendiliğinden düşer. CPU yüksekse sorun ekran kartında değil işlemcidedir. |

## APK nasıl alınır

### Yol A — Otomatik (önerilen, hiçbir şey kurmadan)
Bu repoda `.github/workflows/citysim-android.yml` var. `citysim/` içinde bir değişiklik push edildiğinde GitHub:
1. Godot 4.7.2 ve Android export şablonlarını indirir,
2. Testleri çalıştırır,
3. arm64-v8a **debug imzalı** APK üretir,
4. APK'yı hem Actions "Artifacts" bölümüne hem de **Releases → `citysim-latest`** sürümüne koyar.

Telefondan: repo sayfası → Releases → `citysim-latest` → `SehirSim.apk` indir → "Bilinmeyen kaynaklardan yükleme" iznini ver → kur.

Aynı sayfada `SehirSim-GL.apk` da var: aynı oyunun OpenGL (Compatibility) sürümü, ayrı paket adıyla (`Şehir Sim (GL)`) kurulur. Bazı telefonlarda Vulkan'dan hızlıdır; ikisini karşılaştırmak için.

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
- **Yollar:** yol yükseltme (sokak → cadde) yok, şimdilik yık + yeniden çiz. Serbest el çizimi, köprü/tünel, çıkmaz sokak dönüş cebi ve trafik ışığı yok (ışıklar Faz 6). Kavşak köşeleri çok dar açılarda sadeleşir.
- **Kayıt:** yol ağı henüz kaydedilmiyor (Faz 8).
- **Doku siteleri:** ambientCG ve Poly Haven bu geliştirme ortamından erişilemedi. Yol ve kaldırım dokuları shader ile üretildi, ek dosya yok. Kenney'nin ücretsiz (CC0) şehir modelleri Faz 3'te binalar için kullanılacak.
- Harita boş başlar; inşa araçları (yol çizme) Faz 2'de gelir. Referans bloklar sadece ışık testi için ve varsayılan kapalı.
- Dinamik çözünürlük GPU darboğazını çözer; FPS düşüklüğü CPU kaynaklıysa (ileride kalabalık simülasyon) çözünürlük düşürmek işe yaramaz — o iş Faz 6'daki simülasyon LOD'unun.
- Ağaçlar düşük poligonlu yer tutucu; gerçek ağaçlar için LOD + uzakta billboard (impostor) gerekecek — 1000'lerce ağaçta bu şart.
- Sokak lambaları, araçlar, yağmur/kar, mevsim renkleri yok (Faz 6, 8, 9).
- Su kütleleri ve arazi yüksekliği yok. Fazlar listesinde de yok — **Faz 2 veya 3'e eklemeyi öneririm**, çünkü yol ve imar sistemi suyu/eğimi bilmeli.
- Kayıt sistemi yok (Faz 8); sadece grafik ayarı `user://settings.cfg`'ye kaydediliyor.
- Listedeki diğer sistemler (RoadNetwork, ZoneSystem, …) ilgili fazlarda eklenecek; boş taslak dosya bırakılmadı.
- Gölge kalitesi kamera mesafesine göre otomatik ayarlanıyor; çok uzak harita görünümünde gölgeler yumuşar (bilinçli mobil tercih).
