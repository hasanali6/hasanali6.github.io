# Şehir Simülasyonu — Faz 1–9 (tüm fazlar)

Godot 4.7.2 (Mobile renderer, Vulkan) ile Android için şehir kurma simülasyonu.
**Oyunu nasıl oynayacağını anlatan genel rehber: [OYUN_REHBERI.md](OYUN_REHBERI.md).**
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

## Gelişme, gökdelenler, metro ve hileler

| Parça | Dosya | Ne yapar |
|---|---|---|
| Seviye 1–5 | `data/zones.json` (`floors_by_level`, `growth.max_level`), `data/economy.json` (`rent_level_factor`) | Hak eden binalar 5 seviyeye kadar büyür; yüksek konut ve ofis 40+ kata çıkar. |
| Yoğunlaşma | `building_system.gd` (`_densify`, `_redevelop_site`), `zones.json` → `growth.densify` | Seviye 3+ binalar komşularıyla birleşip üst imara geçer (düşük → orta → yüksek konut, düşük → yüksek ticari, karma → yüksek konut). Talep ≥ 0,1; yükseklik yasağında olmaz. |
| Metro | `data/transit.json` → `types.metro` (`underground`), `transit_system.gd` (`_metro_visuals`, gidiş-dönüş süreleri), `TransitRules.tunnel_path` / `shuttle`, `VehicleModels.metro_entrance` | Yol kenarı istasyonlar, aralarında yumuşak tünel (nehrin altından da). Trenler gidip gelir, yolculuk = iki istasyon arası mesafe. Ücret: hat + istasyon + tünel metresi. Büyük Şehir'de (10.000) açılır. |
| Tren | `transit.json` → `types.train` (`elevated`), `transit_system.gd` (`_train_visuals`, `_move_trains`, `_link_outside`, `has_intercity`), `scripts/world/rail_visuals.gd` | 8 m yükseklikte viyadük, ayaklar boş zemine, istasyon peronları, görünür 3 vagonlu trenler. Uç istasyon harita kenarındaysa şehirlerarası hat: otoyolsuz da tam göç/turizm. Şehir'de (5.000) açılır. |
| Liman ve havalimanı | `catalog.json` → `leisure` (`port`, `airport`, `port_trade_bonus`, `airport_migration_bonus`), `company_system._linked`, `citizen_system` göç, `build_tool._runway_ok`, `vegetation.gd` (pistte ağaç yok) | Liman: deniz ticareti (bağlantısız ticaret tam, ihracat +%15, ithalat −%15). Havalimanı: 45 × 320 m pist alanı ister, göç +%25, turizm. |
| Yayalar ve park etmiş arabalar | `scripts/world/pedestrians.gd`, `assets/materials/pedestrian.gdshader`, `building_system._parts_house` | Sokak nüfusuna göre kaldırımda yürüyen insanlar (hareket shader'da, oyun saatine bağlı, gece azalır; tavan kaliteye göre). Dolu evlerin önünde park etmiş araba. |
| Deniz ve sahil | `data/map.json` → `water.coast`, `MapWater.coast_at/coast_distance`, `water_common.gdshaderinc`, `terrain.gdshader` (kumsal), `terrain_system.gd` (deniz yüzeyi, denizde dağ yok) | Güneyde dalgalı sahil; yollar, imar ve ağaçlar denize girmez. Denize 220 m'ye kadar evler +6 mutluluk. |
| Park ve sahil yapıları | `data/catalog.json` → `leisure`, `scripts/world/leisure_models.gd`, `building_system._report_leisure` | 6 park (oyun parkı, heykelli park, futbol sahası, botanik bahçesi, hayvanat bahçesi, lunapark) ve 6 sahil yapısı (plaj, iskele, deniz feneri, marina, sahil kafesi, sahil oteli). Parka göre etki alanı, aylık turizm geliri ve bakım gideri. |
| Hileler | `scripts/systems/cheats.gd` (autoload `Cheats`), `scripts/ui/cheats_panel.gd` | Ayarlar → Hileler: para ekleme, tüm kilitleri açma, sınırsız para, hızlı büyüme (×3), yoğunlaşma aç/kapa. `settings.cfg` → `[cheats]`. |

## Faz 9: Görsel cila ve ses

| Parça | Dosya | Ne yapar |
|---|---|---|
| PBR dokular | `assets/textures/*.png`, üretici `tools/gen_textures.py` | Asfalt (agrega taşları, çatlaklar), beton kaldırım, sıva, tuğla, kiremit. Her biri renk detayı + pürüzlülük (alfa) + normal haritası; dikişsiz döşenir, telefonda ASTC/ETC2 ile sıkıştırılır, mipmap'li. Yakında tam, uzakta silinerek (titreme yok). |
| Yol "decal"ları | `road_asphalt.gdshader` | Şeritlerde koyulaşmış teker izleri ve yağ çizgisi, yer yer yeni asfaltla yamanmış dikdörtgenler (dikiş çizgili), rögar kapakları. Hepsi shader'da, ek çizim maliyeti yok. |
| Bina yüzeyleri | `building_placeholder.gdshader`, `roof.gdshader` | Alçak ve orta binaların bir kısmı tuğla, diğerleri sıva; sıvada yağmur izleri. Kırma çatılarda kiremit sıraları. Normal haritaları teğet gerektirmeden ışığa tepki verir. |
| Gece ışıkları | `building_placeholder.gdshader`, `beacon.gdshader` | Zemin kat dükkân vitrinleri akşam çoğunlukla yanar ve daha parlaktır; 10+ katlı binaların çatı köşelerinde iki saniyede bir yanıp sönen kırmızı uçak ikaz lambaları. Sokak lambaları, ışık havuzları, araç farları, durak camları önceki fazlardan. |
| Ses | `scripts/systems/audio_system.gd`, `assets/audio/*.ogg`, üretici `tools/gen_sounds.py` | Ortam: trafik uğultusu (yakındaki araç sayısıyla), gündüz kuşlar, yaz geceleri cırcır böcekleri, yağmur, yükseklerde rüzgâr; kamera yüksekliği, saat, mevsim ve havaya göre yumuşakça karışır. Efektler: buton, menü, yol yapma, yıkma, bina koyma, imar fırçası, hata, bildirim, kilometre taşı, para. Sakin bir müzik döngüsü (64 sn). Ayarlar'da Müzik / Efekt / Ortam ses seviyeleri (kaydedilir). Uygulama arka plana geçince ses kesilir. Toplam ses boyutu ~830 KB. |
| Kalite | `data/graphics.json` | Düşük ayarda doku detayı kapalı (`surface_detail`), Orta ve Yüksek'te açık. |

**Test sonrası düzeltmeler:**
- **Bina yıkma:** İnşa Et menüsünde kırmızı **Yık** düğmesi. Dokunulan bina (yoksa yol) kırmızı işaretlenir, bırakınca yıkılır. Elle konan ve hizmet binaları fiyatının yarısını, yollar %75'ini geri verir.
- **Düz yol çizimi:** açı adımları artık başlanan yola göre ölçülüyor ve her zaman 15°'ye kilitleniyor (eskiden ±4° tolerans vardı, parmak titreyince yol eğri/kırık çıkıyordu). Uç nokta yakındaki kavşağa veya yola ancak yön bozulmuyorsa yapışıyor.

- **Kamera kolaylığı:** araç açıkken sağda **İnşa / Kamera** düğmesi; Kamera'da tek parmak haritayı kaydırır, araç açık kalır. İki parmak artık her yönde kaydırır (eskiden dikey kaydırma eğim yapıyordu), döndürme ancak belirgin bir bükmeyle başlar (yakınlaştırırken görüntü dönmez). Solda 45° döndürme ve eğim düğmeleri.

- **Otoyol ve dış bağlantılar:** yeni yol tipi Otoyol (6 şerit + refüj, 100 km/s, kenarında imar yok; İlçe'de açılır). Haritanın doğu ve batı kenarından gelen iki otoyol bağlantısı başta hazır ve yıkılamaz. Yollarını bunlara bağlamak gerekir: bağlı şirketler ihracat yapar ve normal fiyattan ithal eder, kamyonlar harita kenarına gidip gelir, iki bağlantı arasında transit trafik akar. Bağlı olmayan kasabada ihracat %35'e düşer, ithalat %40 pahalı olur, göç yarıya iner, her ay uyarı çıkar.
- **Yol yükseltme:** yol panelinde **Yükselt** modu. Üstte yeni tipi seç, yola dokun: yol yerinde değişir (ör. sokak → cadde). Bedeli yeni yolun fiyatından eskisinin iadesi düşülerek alınır. Genişleyen yol kenardaki parsellerden yer alabilir.
- **Köprüler:** yollar artık suyun üstünden geçebilir. Su üstündeki kısım korkuluklu köprü olur ve metre başına 4 kat pahalıdır. Köprünün iki ucu ve kavşaklar karada olmalı.

- **Üretim zinciri:**
  - Haritada doğal kaynaklar var: verimli toprak, orman, maden, petrol (Katmanlar → Kaynaklar).
  - İnşa Et → **Üretim** ile çiftlik, kereste kampı, maden ocağı ve petrol kuyusu kurulur; kaynak olmayan yere konmaz.
  - Tesisler işçi çalıştırır ve zenginliğe göre hammadde üretir. Maden ve petrol rezervi tükenir; tarla ve orman kirlilikten etkilenir.
  - Fabrikalar önce şehrin hammaddesini kullanır (ithal hammaddeden ucuz); fazlası otoyoldan ucuza ihraç edilir.
  - Kamyonlar tesisten fabrikaya ve harita kenarına gider.
  - Ekonomi → **Üretim** sekmesi: üretilen, kullanılan, ithal ve ihraç edilen hammadde ve mamul ürün.
  - Çiftlik ve kereste Köy'de, maden ve petrol Kasaba'da açılır.

**Neden dokular ve sesler burada üretildi:** bu geliştirme ortamının ağ ayarları ambientcg.com, polyhaven.com, kenney.nl, freesound.org ve opengameart.org'a erişimi engelliyor. Dokular ve sesler bu yüzden repodaki Python betikleriyle sıfırdan üretildi (lisans derdi yok, istenirse yeniden üretilebilir). Ortamın ağ izni açılırsa (bulut ortamı ayarları → Network access → bu alan adlarını ekle) taranmış PBR dokular ve kayıt sesleri aynı dosya adlarıyla değiştirilebilir; kodda değişiklik gerekmez.

**Faz 9 kabul kriterleri:**

| # | Kriter | Nasıl test edilir |
|---|---|---|
| 1 | Asfalt dokusu | Sokak seviyesine in: asfaltta taş dokusu, ince çatlaklar, teker izleri, yer yer yama ve rögar kapağı. |
| 2 | Bina yüzeyleri | Binalara yaklaş: bazılarında tuğla, bazılarında sıva; ışık yön değiştirince derz/pürüz gölgesi. Kırma çatılarda kiremit. |
| 3 | Gece | Saati 21:00'e al: dükkân vitrinleri yanıyor, yüksek binaların köşelerinde kırmızı ikaz lambası yanıp sönüyor. |
| 4 | Ses | Ses açıkken: alçakta kuşlar ve trafik, yükselince rüzgâr, gece cırcır böcekleri, yağmurda yağmur sesi. Yol yap/yık, bina koy → efekt. |
| 5 | Ses ayarları | Ayarlar → Müzik/Efekt/Ortam kaydırıcıları; uygulamayı kapat-aç → seviyeler hatırlanır. |
| 6 | Düşük kalite | Ayarlar → Düşük: doku detayı ve yağmur parçacıkları kapanır, FPS artar. |
| 7 | Testler | `godot --headless --path citysim -s res://tests/run_tests.gd` → `164 checks, 0 failed`. |

## Faz 8: İlerleme, kayıt, hava ve mevsim, optimizasyon, kalite

| Parça | Dosya | Ne yapar |
|---|---|---|
| Kilometre taşları | `scripts/systems/progression_system.gd`, `scripts/data/progression_rules.gd`, `data/progression.json` | Mezra (0) → Köy (300) → Kasaba (1.000) → İlçe (2.500) → Şehir (5.000) → Büyük Şehir (10.000) → Metropol (25.000) → Megakent (50.000). Her taşta para ödülü, daha yüksek kredi limiti ve yeni araçlar. Kilitli yol/imar/bina/hizmet/hat düğmeleri gri görünür; dokununca "… olunca açılır" der. |
| Harita genişlemesi | `road_tool.gd`, `terrain.gdshader` | Başta merkezdeki 2,4 km × 2,4 km'ye yol yapılır, Kasaba'da 3,2 km, Şehir'de tüm 4 km açılır. Kilitli kısım hafif gölgeli, sınırı kesik çizgili. |
| İlerleme sekmesi | `scripts/ui/economy_panel.gd` | Ekonomi → İlerleme: unvan, sonraki taşa ilerleme çubuğu, ödül ve açılacaklar listesi. |
| Kayıt yuvaları | `scripts/systems/save_system.gd`, `scripts/ui/saves_panel.gd` | Ayarlar → Kayıtlar: otomatik kayıt + 3 yuva. Her biri tarih, unvan, nüfus ve para gösterir. Yükleme sahneyi temizden açar (eski şehirden iz kalmaz). Kayıt biçimi sürümlü; eski kayıtlar açılır. |
| Hava ve mevsim | `scripts/systems/weather_system.gd`, `data/weather.json` | Açık, bulutlu, yağmurlu, karlı (kar sadece kışın). Mevsim takvimden: bir oyun günü bir ay, mevsim 3 gün sürer. Yağmurda yollar ıslanır (koyu, parlak, su birikintili), sonra kurur; kar yağınca zemin, kaldırım, çatı ve ağaçlar beyazlar, kar yavaş erir; sonbaharda yaprak döken ağaçlar sarı-turuncu-kırmızı olur. Saatin yanında hava ikonu ve mevsim adı. |
| Hava etkileri | `traffic_system.gd`, `traffic_rules.gd`, `service_system.gd`, `day_night_cycle.gd` | Yağmurda araçlar %12, karda %20 yavaş, yollar daha çabuk tıkanır (rota değişir). Bulutta güneş santrali az üretir, rüzgârda türbin biraz fazla. Işık kararır, gölgeler yumuşar, sis artar. |
| Yağmur/kar efekti | `scripts/world/weather_effects.gd` | Kameranın önünde GPU parçacıkları; yükseğe çıkınca seyrelir. Ayarlar → "Hava durumu" ile kapatılabilir. |

**Optimizasyon turu (ölçülen):**
- Bina çizimi: bina parçaları önbellekte, her MultiMesh tek seferde dolduruluyor ve bir karedeki bütün değişiklikler tek çizimde birleşiyor → test şehrinde bina başına süre yarıya indi (4–7 ms → ~2 ms), büyüyen şehirde art arda çizim yok.
- İmar katmanı ve ağaç temizleme de birleştirildi (ağaçlar en fazla yarım saniyede bir yeniden hesaplanıyor; önceden her bina büyümesinde 3–4 ms).
- Hat araç sayısı artık anında okunuyor (önceden her yarım saniyede bütün araçlar taranıyordu).
- Görselsiz oyun döngüsü (test şehri, 4 hat, yağmur): karelerin %95'i kare sınırında (16,7 ms), 900 karede tek bir 23 ms'lik sıçrama.

**Kalite ayarları:** Düşük / Orta / Yüksek artık yağmur-kar parçacıklarını da belirliyor (Düşük kapalı, Orta 1.500, Yüksek 3.000). Gölge, çizim mesafesi, araç tavanı, gece gölgesi önceki gibi.

**Faz 8 kabul kriterleri:**

| # | Kriter | Nasıl test edilir |
|---|---|---|
| 1 | Sınırlı başlangıç | Yeni şehir: sadece sokak/tek yön sokak, düşük konut, düşük ticari, sanayi ve temel hizmetler açık; cadde, bulvar, ofis, otobüs vb. gri. Gri düğmeye dokun → "Köy (300 nüfus) olunca açılır". |
| 2 | Kilometre taşı | Nüfus 300'ü geçince "Tebrikler! Şehrin artık bir Köy" bildirimi, +5.000, cadde ve otobüs açılır, kredi limiti artar. |
| 3 | Harita sınırı | Kesik çizginin dışına yol çizmeye çalış → "Harita burada henüz kilitli". Kasaba olunca çizgi genişler. |
| 4 | İlerleme sekmesi | Ekonomi → İlerleme: unvan, ilerleme çubuğu, sonraki ödül ve açılacaklar. |
| 5 | Kayıt yuvaları | Ayarlar → Kayıtlar → Yuva 1 Kaydet. Biraz oyna, Yuva 1 → Yükle'ye iki kez dokun → şehir o anki hâline döner. |
| 6 | Hava | Oyunu 1x'te bırak: birkaç dakikada bir hava değişir, ikon güncellenir. Yağmurda yollar parlar ve damlalar düşer, durunca kurur. |
| 7 | Mevsim | Aralık–Şubat kış: kar yağabilir, şehir beyazlar. Eylül–Kasım ağaçlar sararır. |
| 8 | Hava trafiği etkiler | Yağmurda Katmanlar → Trafik daha kırmızı, işe gidiş süresi biraz uzar. |
| 9 | Ayarlar | "Hava durumu" kapatılınca yağmur/kar durur. Düşük kalitede parçacık yok. |
| 10 | Testler | `godot --headless --path citysim -s res://tests/run_tests.gd` → `164 checks, 0 failed`. |

## Faz 7: Toplu taşıma, bölgeler ve politikalar

| Parça | Dosya | Ne yapar |
|---|---|---|
| Hat hesapları | `scripts/data/transit_rules.gd` | Durakların sırasıyla dolaşan kapalı güzergâh (yol ortasında U dönüşü yok, hat döngü kurmalı), duraklar arası mesafe, araba–toplu taşıma seçimi, bölge çokgeni kontrolleri. Görselsiz test edilir. |
| Toplu taşıma | `scripts/systems/transit_system.gd`, `data/transit.json` | Otobüs ve tramvay hatları: yola dokununca durak, "Hattı aç" ile hat açılır. Tramvay sadece cadde ve bulvarda. Her hattın rengi, araç sayısı (−/+), yolcu ve doluluk bilgisi var; bilet fiyatı bütün hatlarda ortak. Durak kulübesi (otobüs), peron (tramvay), tramvay rayları; çizerken ve Katmanlar → Toplu taşıma'da renkli hat şeritleri. |
| Hat araçları | `scripts/world/vehicle_system.gd`, `vehicle_models.gd` | Otobüs (12 m) ve tramvay (18 m) hat boyunca sağ şeritte döner, her durakta 6–8 sn bekler, kaybolmaz. Kaybolan araç (yol düzenleme, kalite değişimi) kendiliğinden geri gelir. |
| Araç mı otobüs mü | `scripts/systems/traffic_system.gd` | İki ucu da bir durağa yürüme mesafesinde (450 m) olan yolculuklar arabayı (sürüş + park yeri arama + otopark ücreti) toplu taşımayla (yürüme + bekleme + yolculuk + bilet) karşılaştırır; bir kısmı arabayı bırakır. Hat doluysa fazlası tekrar arabaya döner. İşe gidiş süresi otobüse binenlerin süresiyle karışık hesaplanır. |
| Bölgeler | `scripts/systems/district_system.gd`, `data/districts.json` | Haritaya köşe köşe dokunarak bölge çiz, ilk köşeye dokununca kapanır (son köşeye dokunmak geri alır). Kendini kesen sınır kabul edilmez. Bölge adı haritada yazar, panelden değiştirilir. |
| Politikalar | `district_system.gd` + trafik, bina, hizmet, vatandaş sistemleri | **Ağır araç yasağı:** kamyonlar bölgenin içinden geçmemeye çalışır, gürültü %40 azalır (+2 mutluluk). **Yüksek bina yasağı:** yeni ve büyüyen binalar en fazla 4 kat (+1). **Geri dönüşüm:** çöp %35 azalır, kişi başı aylık 0,6 maliyet (+1). **Ücretli otopark:** bölgeye arabayla gelen 1,5 öder, şehre gelir; daha çok kişi otobüse biner (−1). |
| Paneller | `scripts/ui/transit_panel.gd`, `scripts/ui/district_panel.gd` | İnşa Et → **Ulaşım** ve **Bölgeler** artık açık. |
| Bütçe | `scripts/systems/economy_system.gd` | Gelir: bilet, otopark. Gider: toplu taşıma araç bakımı, geri dönüşüm. Ekonomi → Bütçe'de satır satır. |

**Hızlı sayılar (`data/transit.json`):** otobüs hattı 2.000 + durak başına 500, araç başı aylık 180, günde araç başı 450 yolcu taşır. Tramvay hattı 8.000 + durak başına 1.500, araç başı aylık 420, günde araç başı 1.100 yolcu. Varsayılan bilet 2 (0–6 arası, 0,5 adım).

**Bu fazda düzeltilen eski hatalar:**
- **Yol yapınca bütün binalar siliniyordu.** Binalar varken yeni yol çizilince (Faz 3'ten beri) şehirdeki her bina kayboluyordu: hücreleri toplayan kod listeyi geçici bir kopyaya ekliyordu. Düzeltildi; artık sadece yolun gerçekten kestiği binalar yıkılır.
- Oyun açıkken kayıt yeniden yüklenince eski hane numaraları evlerde kalıyordu (hata mesajı ve "0 kişi"); yükleme artık evleri boş başlatıyor.

**Ölçümler (geliştirme bilgisayarı):** bir yolculuk için toplu taşıma süresi sorgusu ~4 µs (önbellekli). Test şehrinde (4 hat, 2 bölge) 900 kare gerçek oyun döngüsü: 14 trafik turu, bütün hat araçları yolda, kayıp araç 0.

**Faz 7 kabul kriterleri:**

| # | Kriter | Nasıl test edilir |
|---|---|---|
| 1 | Otobüs hattı | İnşa Et → Ulaşım → Otobüs. Bir yapı adasının çevresindeki yollara 3–4 durak koy, "Hattı aç". Hat rengiyle şerit çıkar, duraklarda kulübe belirir, otobüsler durakta durup devam eder. |
| 2 | Geçersiz hat | Çıkmaz bir yolun iki ucuna durak koy → "dönen bir güzergâh yok" uyarısı, hat açılmaz. Duraklar çok yakınsa / yol dışındaysa uyarı. |
| 3 | Tramvay | Cadde veya bulvarlardan bir döngü kur, tramvay seç, durak koy. Sokağa durak koyunca "Tramvay sadece cadde ve bulvarlarda çalışır". Rayda tramvay, durakta peron. |
| 4 | Yolcu ve kalabalık | Panelde hat seç: yolcu/gün, doluluk %, uzunluk, sefer aralığı. Araç ekle/çıkar → kapasite ve sefer aralığı değişir. Bilet fiyatını artır → yolcu azalır. |
| 5 | Mod seçimi | Katmanlar → Toplu taşıma: durağa yakın sokaklar yeşil; açıklamada "yolculukların %N'i toplu taşımayla". Hat açınca birkaç saniyede yollardaki araba trafiği hafifler. |
| 6 | Bölge çizme | İnşa Et → Bölgeler. Haritaya köşe köşe dokun, ilk köşeye dokun → bölge oluşur, adı haritada çıkar. Panelden adını değiştir. Kendini kesen sınır → uyarı. |
| 7 | Politikalar | Ağır araç yasağı → kamyonlar bölgeden geçmez (başka yol varsa). Yüksek bina yasağı → yeni binalar en fazla 4 kat. Geri dönüşüm → Bütçe'de geri dönüşüm gideri. Ücretli otopark (işyeri olan bölgede) → Bütçe'de otopark geliri. |
| 8 | Bütçe | Ekonomi → Bütçe: bilet gelirleri, otopark ücretleri, toplu taşıma ve geri dönüşüm giderleri. |
| 9 | Kayıt | Uygulamayı kapat-aç: hatlar, araç sayıları, bilet fiyatı, bölgeler, adlar ve politikalar geri gelir. |
| 10 | Yol düzenleme | Hattın geçtiği yolu yık → hat "çalışmıyor" olur, araçları kalkar; binalar sadece yıkılan yolun kenarında gider. |
| 11 | Testler | `godot --headless --path citysim -s res://tests/run_tests.gd` → `151 checks, 0 failed`. |

## Faz 6: Trafik

| Parça | Dosya | Ne yapar |
|---|---|---|
| Yol ağı kopyası | `scripts/data/traffic_graph.gd` | Yol ağının paketli dizilerde (CSR) salt okunur kopyası. Oyuncu yol çizerken arka plandaki hesap kendi kopyasıyla çalışır. |
| Trafik kuralları | `scripts/data/traffic_rules.gd` | BPR sıkışıklık eğrisi (yol doldukça hız düşer), en kısa süre ağaçları, akışı ağaç boyunca biriktirme, iki fazlı sinyal grupları, sağa/sola dönüş, araç hareket modeli (shader ile birebir aynı formül). |
| Akış ataması | `scripts/data/traffic_assignment.gd` | Günün bütün yolculuklarını sıkışıklığa göre en hızlı yoldan gönderir, yollara yükler ve bir önceki turla yumuşatır; dolu yoldan kaçan sürücüler başka yol bulur. Rotalar önbelleğe alınır, her turda (8 sn) yenilenir. `WorkerThreadPool` iş parçacığında çalışır, oyunu durdurmaz. |
| Şerit geometrisi | `scripts/data/lane_geometry.gd` | Her şerit ve kavşaktaki her şeritten şeride bağlantı bir çizgi; hepsi tek bir GPU dokusuna paketlenir. Değişmeyen yolların şeritleri yeniden kullanılır. Trafik sağdan akar. |
| Trafik sistemi | `scripts/systems/traffic_system.gd` | Talep: her çalışan ev → iş → ev, haneler alışverişe, sanayiden dükkânlara kamyon, hizmet binalarından evlere çöp kamyonu, polis, ambulans, itfaiye, cenaze aracı. Sonuç: yol başına günlük araç ve hız, ev-iş arası süre, yol gürültüsü. Yola uzun basınca yol bilgisi, sıkışıklıkta uyarı. |
| Araçlar | `scripts/world/vehicle_system.gd`, `vehicle_models.gd`, `assets/materials/vehicle.gdshader` | Sedan, hatchback, minibüs, kamyon, polis, ambulans, itfaiye; iki renkli boya, camlar, farlar (gece yanar), stop lambaları (frende yanar), tepe lambası (yanıp söner). Araçlar ekran kartında hareket eder; işlemci sadece bir olay olunca (şerit sonu, ışık değişimi, kuyruk) o aracı günceller. |
| Trafik ışıkları | `vehicle_system.gd`, `assets/materials/traffic_light.gdshader` | Cadde ve bulvar kavşaklarında iki fazlı ışık (yeşil 14 sn, sarı 3, hepsi kırmızı 1,5). Kırmızıda kuyruk, yeşilde araçlar sırayla kalkar; dolu şeride girmezler (kavşak tıkanmaz). |
| Katman | `scripts/world/info_overlay.gd` | Katmanlar → Trafik: yollar doluluğa göre yeşil / sarı / kırmızı, evler işe gidiş süresine göre boyanır. |

**Simülasyon LOD (üç kademe):**
- **Yakın:** kameranın çizim mesafesindeki araçlar çizilir (Düşük 700 m, Orta 1.100 m, Yüksek 1.600 m), tek MultiMesh ile model başına bir çizim.
- **Uzak:** araçlar veri olarak sürmeye devam eder ama çizilmez (shader onları sıfıra küçültür).
- **İstatistiksel:** günün bütün yolculukları, görünsün görünmesin, akış atamasında sayılır ve yol hızlarını belirler.
- Görünen araç sayısı: kalite tavanı (Düşük 300, Orta 800, Yüksek 1.500) ile günlük yolculuk sayısının %20'sinden küçük olanı, günün saatine göre (sabah ve akşam yoğun, gece az). Kameranın baktığı yere yakın yolculuklar öncelikli.

**Mutluluk:** işe gidiş 15 dakikayı geçince dakika başına −0,35 (en fazla −15); yoğun yolun kenarındaki evlere gürültü (en fazla −6). Eve uzun basınca "İşe gidiş: N dk".

**Ölçümler (geliştirme bilgisayarı):** test şehri (51 kavşak, 65 yol, ~900 nüfus) için atama 4 ms, araçlar kare başına ~0,06 ms. Büyük ızgara (900 kavşak, 1.740 yol, 20.000 yolculuk): atama 2,5 sn (arka planda), şerit geometrisi ilk kurulumda 266 ms, yol değişince 69 ms. Telefonda bu sürelerin 3–4 katı beklenir.

**Faz 6 kabul kriterleri:**

| # | Kriter | Nasıl test edilir |
|---|---|---|
| 1 | Sabah işe, akşam eve trafik | Konut + iş yeri imar et, nüfus gelsin. Saat 7–9 ve 16–19 arası yollar dolar, gece seyrelir. |
| 2 | Araçlar sağdan gider ve şerit seçer | Sokak seviyesine yaklaş: araçlar sağ şeritte, sağa dönecekler sağ şeride, sola dönecekler sol şeride geçer, kavşakta kavis çizerek döner. |
| 3 | Trafik ışıkları | Cadde/bulvar kavşağında direklerde kırmızı-sarı-yeşil; kırmızıda kuyruk, yeşilde sırayla kalkış. Gece farlar ve stop lambaları yanar. |
| 4 | Sıkışıklık ve alternatif rota | Bütün trafiği tek bir sokağa bağla → Katmanlar → Trafik'te kırmızıya döner, "Trafik sıkışık" uyarısı gelir. Paralel bir cadde çiz → birkaç saniye içinde trafik bölünür, renk düzelir. |
| 5 | Yol bilgisi | Bir yola uzun bas: şerit sayısı, hız sınırı, günlük araç, yoğunluk, ortalama hız, uzunluk. |
| 6 | İşe gidiş süresi | Bir eve uzun bas: "İşe gidiş: N dk". Uzak iş yerleri ve sıkışık yollar süreyi ve mutsuzluğu artırır. |
| 7 | Hizmet araçları | Çöp kamyonu (yeşil-beyaz), polis (tepe lambalı), ambulans, itfaiye, cenaze aracı ilgili binalardan çıkar. |
| 8 | Kalite ayarı | Ayarlar → Düşük/Orta/Yüksek: araç tavanı ve çizim mesafesi değişir. |
| 9 | Yol düzenleme | Yol ekle/sil: etkilenmeyen araçlar yoluna devam eder, kesilen yoldakiler kaybolur, yeni rotalar birkaç saniyede gelir. |
| 10 | Testler | `godot --headless --path citysim -s res://tests/run_tests.gd` → `143 checks, 0 failed`. |

## Faz 5: Hizmetler ve altyapı (+ grafik geçişi)

| Parça | Dosya | Ne yapar |
|---|---|---|
| Elektrik | `data/services.json`, `scripts/systems/service_system.gd` | Kömür (60 MW), doğalgaz (40 MW), rüzgâr türbini (3 MW), güneş santrali (8 MW). Kablolar yolları izler: santral hangi yol ağına bağlıysa o ağı besler. Binalar en eskiden başlayarak sırayla beslenir; güç yetmezse kalanlar elektriksiz kalır. |
| Su ve atık su | aynı | Su pompası ve atık su çıkışı / arıtma tesisi (üçü de nehir ya da göl kıyısına kurulur). Borular yolların altında, otomatik. Pompa arıtılmamış bir çıkışa 380 m'den yakınsa musluktan kirli su akar. |
| Hizmetler | aynı + `scripts/data/service_rules.gd` | Sağlık ocağı, hastane, ilkokul, lise, üniversite, karakol, itfaiye, çöp depolama, çöp yakma, mezarlık, krematoryum. Her birinin yol ağı üzerinden ölçülen bir kapsama yarıçapı (Dijkstra), kapasitesi ve bakımı var. Kapasite aşılırsa verim ve kapsama düşer; çöp alanı ve mezarlık zamanla dolar. |
| Etkiler | `citizen_system.gd`, `company_system.gd`, `building_system.gd` | Kapsama mutluluk verir; eksik hizmet şehir büyüdükçe (1.500 nüfusa kadar kademeli) mutluluğu düşürür. Sağlık ölümleri azaltır; lise ve üniversite, büyüyen çocukların eğitimini yükseltir. Elektriği/suyu olmayan şirket %30 kapasiteyle çalışır, binada uyarı ikonu çıkar, 6 ay sürerse bina terk edilir; göçmenler böyle evleri seçmez. Nüfus 800'ü geçince itfaiye olmayan yerde yangın çıkabilir. Santral, çöp yakma ve sanayi kirliliği mutluluğu düşürür. |
| Bütçe ve ücretler | `scripts/systems/economy_system.gd`, `scripts/ui/economy_panel.gd` | Ekonomi → **Hizmetler**: her kategori için %50–150 bütçe (gider ve verim birlikte değişir), elektrik ve su ücreti (%50–150: yüksek ücret daha çok gelir, daha az mutluluk ve tüketim). Bütçe sekmesi iki sütun: ücret gelirleri ve kategori kategori hizmet giderleri. |
| Katmanlar | `scripts/world/info_overlay.gd`, `assets/materials/info_overlay.gdshader` | Soldaki turkuaz düğme: elektrik, su, sağlık, eğitim, polis, itfaiye, çöp, defin, kirlilik ve mutluluk ısı haritaları. Arazi griye döner, hücreler ve binalar kırmızı → sarı → yeşil boyanır, hizmet binaları mavi. Hizmet yerleştirirken ilgili katman kendiliğinden açılır. |
| Uyarı ikonları | `assets/materials/icon_billboard.gdshader` | Elektriksiz binada turuncu şimşek, susuz binada mavi damla; kameraya döner, uzaklaştıkça büyür. |
| Modeller | `scripts/world/service_models.gd` + `rotor/solar_panel/smoke.gdshader` | Soğutma kulesi ve buhar, dönen rüzgâr pervaneleri, güneş paneli sıraları, hastane (kırmızı haç, helipad), okul (futbol sahası, bayrak), kubbeli ve sütunlu üniversite, karakol (araçlar), itfaiye (garaj kapıları, kule, itfaiye aracı), çöp tepeleri, mezarlık (mezar taşları, şapel, ağaçlar), nehre inen borular; fabrika bacaları da tüter. |

**Grafik geçişi (aynı fazda):** nehir ve göller (dalga, kıyı köpüğü, kumsal), çevrede dağ halkası, ormanlar (~31 bin ağaç, rüzgârda sallanır), cadde ve bulvar ağaçları, bahçe / meydan / otopark / avlu zeminli arsalar, yumuşak temas gölgeleri, kademeli gökdelenler, çatı ekipmanları ve tenteler.

**Kare süresi:** Kapsama her karede en fazla 1,5 ms çalışır (bir hizmet bir kerede); elektrik/su geçişi binaları 200'lük parçalar halinde ve saniyede en fazla bir kez dolaşır. 94 binalı test şehrinde tam geçiş 0,7 ms.

**Faz 5 kabul kriterleri:**

| # | Kriter | Nasıl test edilir |
|---|---|---|
| 1 | Elektrik/su yokken uyarı çıkar | Yol + konut imarı yap, binalar dolsun → çatılarda turuncu şimşek ikonu, "N binada elektrik yok" bildirimi. |
| 2 | Elektrik yol ağıyla dağılır | İnşa Et → Altyapı → Rüzgâr türbini, aynı yola bağla → ikonlar kaybolur. Bağlantısız ayrı bir yoldaki evler elektriksiz kalır. |
| 3 | Su tesisleri kıyıya kurulur | Pompayı nehirden uzağa koymaya çalış → kırmızı önizleme, "Nehir ya da göl kıyısına kur". |
| 4 | Kirli su | Atık su çıkışını pompanın yanına kur → evin bilgi kartında "Musluktan kirli su akıyor!". Arıtma tesisi bunu yapmaz. |
| 5 | Kapsama ısı haritası | Sağlık ocağı kur → Katmanlar → Sağlık: çevresi yeşil, yol boyunca uzaklaştıkça sarı ve kırmızı. |
| 6 | Bütçe kaydırıcıları | Ekonomi → Hizmetler → Sağlık %50: gider düşer, yeşil alan daralır; %150: genişler. |
| 7 | Ücretler | Elektrik ücretini %150 yap → ay sonunda "Elektrik ücretleri" geliri artar, mutluluk biraz düşer. |
| 8 | Bütçe satırları | Ay sonunda Bütçe sekmesinde her hizmetin gideri ve ücret gelirleri görünür. |
| 9 | Uzun süre elektriksiz/susuz kalan bina terk edilir | 6 oyun ayı elektrik/su kurma → "N bina terk edildi" bildirimi, binalar kararır. Bilgi kartı kalan süreyi gösterir. |
| 10 | Hizmet bilgisi | Hizmet binasına uzun bas → bakım, hizmet verilen / kapasite, kapsama km'si, (varsa) doluluk ve üretim. |
| 11 | Kayıt | Uygulamayı kapat-aç → hizmet binaları, bütçeler, ücretler ve çöp/mezarlık doluluğu yerinde. |
| 12 | Testler | `godot --headless --path citysim -s res://tests/run_tests.gd` → `116 checks, 0 failed`. Tüm hizmetlerle 6 aylık entegrasyon testinde nüfus 0 → ~750, mutluluk ~%75. |

**Önemli — eski şehir:** Faz 4'te kurduğun şehirde santral ve pompa yok. Güncellemeden sonra binalarda uyarı ikonları çıkar; 6 oyun ayı (1x hızda yaklaşık 36 dakika) içinde elektrik (ör. 1–2 rüzgâr türbini) ve su (pompa + atık su çıkışı) kurmazsan dolu binalar terk edilmeye başlar.

## Faz 4: Ekonomi çekirdeği (+ elle yerleştirme ve kayıt)

| Parça | Dosya | Ne yapar |
|---|---|---|
| Haneler | `scripts/data/household_data.gd`, `scripts/systems/citizen_system.gd` | Haneler paketli dizilerde: yetişkin/çocuk/yaşlı, yetişkin başına eğitim (3 seviye) ve iş, para, mutluluk. Göç gelir/gider; doğum, büyüme, emeklilik, ölüm, evden ayrılıp yeni hane kurma. |
| Konut / iş / alışveriş seçimi | aynı | Göçmen birkaç boş evi örnekler; kira, yakında dükkân ve park puanına göre seçer. İşçi yakın şirketleri örnekler, eğitimine uygun işi tercih eder; fazla eğitimli alt seviye işe girebilir. Her hane en yakın dükkândan alışveriş yapar. |
| Şirketler | `scripts/systems/company_system.gd` | Her ticari/ofis/sanayi/karma binada bir şirket. Sanayi mal üretir (önce şehrin dükkânlarına, kalan ihraç), dükkân hanelere satar (yerel mal yetmezse ithal eder, işçi başına satış kapasitesi var), ofis hizmet üretir. Kâra göre işçi alır/çıkarır; borç batağında kalan iflas eder, bina terk edilir. |
| Bütçe | `scripts/systems/economy_system.gd`, `scripts/ui/economy_panel.gd` | Aylık: konut vergisi (eğitim seviyesine göre ayrı oran), ticari/ofis/sanayi vergisi (kârdan), azalan devlet desteği; gider olarak yol bakımı ve kredi taksiti. Vergi aralığı %-10…%30. Tek ayarlanabilir kredi; limit nüfusla büyür, faiz kullanılan limitle artar, taksit otomatik. |
| RCI talep | `scripts/data/economy_rules.gd`, `scripts/systems/demand_system.gd` | Boş iş/işsiz dengesi, boş konut, mutluluk, vergi, mal eksikliği, ithalat ve eğitimli işsizlerden konut/ticari/ofis/sanayi talebi. Binalar sadece talep varken büyür; göç ayrı bir "çekicilik" değerine bakar. |
| Binaların hayatı | `scripts/systems/building_system.gd` | Kapasite: konut = kat × hücre × yoğunluk hane; iş = kat × hücre × yoğunluk, eğitim karışımına göre. Seviye atlama: konut dolu ve mutluysa, şirket birkaç ay kârdaysa. Talep yokken boş kalan ev ve iflas eden şirket terk edilir (karartılır), birkaç ay sonra yıkılır. |
| Elle yerleştirme | `data/catalog.json`, `scripts/world/build_tool.gd`, `scripts/ui/catalog_panel.gd` | İnşa Et → Binalar: ev, apartman, kule, dükkân, AVM, ofis, fabrika, atölye, park, koru, çeşmeli meydan. Yola yakın sürükle → yeşil önizleme → bırak. Parkların çevresindeki hanelerin mutluluğu artar. |
| Kayıt | `scripts/systems/save_system.gd` | Her ay ve uygulama arka plana atılınca / kapanınca otomatik kayıt; açılışta otomatik yükleme. Ayarlar → Kaydet / Yeni şehir (iki kez dokun). Kayıt sürümlü. |

**Simülasyon LOD:** Her hane ayda tam bir kez güncellenir ama bu iş ayın tiklerine eşit dağıtılır. 10.000 hanede bile tik başına birkaç hane işlenir, kare süresi şehir büyüklüğünden bağımsız kalır. Şirketlerin aylık defteri ay sonunda kapanır (sayıları binlerle sınırlı).

**Arayüz:** Sol üstte nüfus ve ortalama mutluluk; altında K/T/O/S talep çubukları. Para altında aylık net. Sol yeşil düğme ekonomi paneli (Bütçe / Vergiler / Kredi). Bir binaya uzun basınca hane veya çalışan sayısı ve aylık kâr.

**Faz 4 kabul kriterleri:** konut imar edilince göçmen gelir, nüfus ve mutluluk görünür · iş yeri olmadan işsizlik artar, konut talebi düşer, sanayi/ticari talebi yükselir · vergi artınca gelir artar, talep ve mutluluk düşer · ay sonunda bütçe kesilir, para altında aylık net görünür · kredi alınır, taksit her ay düşer · zarar eden şirket işçi çıkarır, sonunda iflas edip bina terk edilir · uygulama kapanıp açılınca şehir yerinde durur. Otomatik testler: `93 checks, 0 failed`; 10 aylık entegrasyon testinde nüfus 0 → ~800, aylık net ~+11.000.

**Bilinçli basitleştirmeler:** göçmenlerin eğitimi rastgele gelir (Faz 5'ten beri şehirde büyüyen çocuklar okullara göre eğitilir) · arsa değeri yok (kira bina seviyesine bağlı) · işe uzaklık kuş uçuşu (trafik süresi Faz 6) · sanayinin tek ürünü "mal", hammadde zinciri ve ürün tipine göre vergi daha sonra · hizmet bütçeleri ve elektrik/su ücretleri Faz 5'te geldi. Tüm denge sayıları `data/economy.json` ve `data/services.json`'da.

## Faz 3: İmar ve binalar

| Parça | Dosya | Ne yapar |
|---|---|---|
| İmar hücreleri | `scripts/data/zone_grid.gd` | Cities: Skylines gibi her yolun iki yanında yola hizalı 8 m hücre sıraları (en fazla 6 derinlik). Eğri ve çapraz yollarda da çalışır. Başka yolun ya da eski bir bloğun üstüne düşen hücre atılır; sıra ilk engelde durur, böylece her hücrenin yola erişimi olur. Paketli diziler, görselsiz test edilebilir. |
| İmar sistemi | `scripts/systems/zone_system.gd` | Yol değişince hücreleri yeniden üretir; yol bölünse bile imar yerinde kalır. İmarlı boş hücreler soluk renkte, imar aracı açıkken tüm hücreler görünür. |
| İmar aracı | `scripts/world/zone_tool.gd` | Fırça, sıra doldurma (bir dokunuşla bloğun tamamı), silgi (üstündeki binayı da yıkar). İmar ücretsiz. |
| Binalar | `scripts/systems/building_system.gd`, `data/zones.json` | İmarlı, yola bakan boş hücrelerde rastgele parsel (genişlik × derinlik) aranır, sığarsa bina yükselerek kurulur. Ay geçtikçe seviye 1→3 atlar ve yükselir. Yol yıkılıp arsası giden bina kaldırılır. Uzun basınca bina bilgisi. |
| Görseller | Kenney modelleri (CC0) + kod | Düşük yoğunluk ticari: Kenney dükkanlar · Orta yoğunluk / karma: Kenney apartmanlar (büyüyünce apartmana dönüşür) · Düşük yoğunluk konut: çatılı evler · Yüksek yoğunluk / ticari: kuleler · Ofis: cam kuleler · Sanayi: fabrika + baca. Hepsi MultiMesh. Gece pencereler yanar. |

**İmar tipleri:** konut düşük/orta/yüksek · ticari düşük/yüksek · ofis · sanayi · karma (zemin dükkân + üst konut).

**Kullanım:** İnşa Et → İmar → tip seç → fırçayla yol kenarındaki hücreleri boya (ya da Doldur ile bloğun tamamı). Oyun 1x/2x/3x hızda akarken binalar kendiliğinden gelir.

**Faz 3 kabul kriterleri:** yol yapınca iki yanında hücre çıkar · hücreler yola ve birbirine binmez · boyanan hücrede zamanla bina büyür · bina yola bakar · seviye atlayınca yükselir · yolu yıkınca arsası giden bina kalkar · yol bölününce imar kaybolmaz. Otomatik testler: `75 checks, 0 failed`.

**Şimdilik basit tutulanlar (Faz 4'te gerçekleşecek):** büyüme hızı sabit (gerçek RCI talebi yok), bina içinde hane ve şirket yok, seviye atlama rastgele. Nüfus göstergesi bu yüzden hâlâ 0.

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
| 2 | Birim testleri geçer | `godot --headless --path citysim -s res://tests/run_tests.gd` → `116 checks, 0 failed` |
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

APK'lar her derlemede aynı sabit test anahtarıyla imzalanır (`.github/citysim-debug.keystore`) ve sürüm numarası artar, yani yeni sürüm eskisinin üstüne güncelleme olarak kurulur. 31 Ekim 2026'dan önceki APK'lar her seferinde farklı anahtarla imzalanıyordu; onlardan geçerken eski uygulamayı **bir kez** kaldırman gerekir. Bu anahtar sadece test içindir; Play Store'a çıkarken ayrı bir yayın anahtarı GitHub secret olarak saklanmalı, asla repoya konmamalı.

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
- **Görsel cila ve ses (Faz 9):** dokular ve sesler sentetik (taranmış fotoğraf/kayıt değil, nedeni yukarıda). Bina modelleri hâlâ prosedürel kutu + Kenney kiti; gerçek bina modelleri yok. Gece ışıkları emisyonla, binalara gerçek ışık düşmüyor (mobil bütçe). Ses 3B konumlu değil (araç sesi tek tek duyulmaz), tek müzik parçası var. Su yüzeyi ve araçlarda yeni doku yok.
- **İlerleme, kayıt, hava (Faz 8):** harita karoları tek tek satın alınmıyor; açık alan kilometre taşlarıyla kare olarak büyüyor. Kilitlemeler sadece yeni inşaatı etkiler; eski kayıttaki caddeler/bulvarlar yerinde kalır. Bulut kaydı ve şehir adı yok. Kaza, sel, yıldırım yok; su yüzeyinde yağmur halkaları yok. Kar trafikte yolları kapatmaz, kar küreme aracı yok. Mevsimler ekonomiyi (ısınma, turizm) etkilemiyor.
- **Toplu taşıma ve bölgeler (Faz 7):** metro, tren, liman ve şehir dışı bağlantıları yok (dış bağlantılar ve otoyol sonraki fazlarda). Aktarma yok: bir yolculuk tek hatla yapılır. Yolcular sayısal; durakta bekleyen ya da araca binen yaya görünmüyor. Otobüs ve tramvay diğer trafikle aynı sağ şeritte gider (ayrı otobüs/tramvay şeridi yok) ve U dönüşü yapamaz, bu yüzden her hat bir döngü olmalı. Var olan hattın durakları düzenlenemez; sil ve yeniden çiz. Tramvay için ayrı ray yolu yok, cadde/bulvarda asfalta gömülü ray çizilir. Hat ve politika ücretleri ilk ayar; denge oynanarak ayarlanacak (küçük kasabada hatlar zarar eder, bu bilinçli). Bölgeler sadece politika içindir, bölge başına vergi yok. Yüksek bina yasağı var olan yüksek binaları yıkmaz, sadece büyümeyi durdurur.
- **Trafik (Faz 6):** kaza ve yağmurda rota değişimi yok (hava Faz 8). Kavşakta çarpışma kontrolü yok: aynı fazda karşıdan sola dönenle düz giden üst üste geçebilir; ışıksız sokak kavşaklarında öncelik kuralı yok, araçlar durmadan geçer. Şerit değiştirme kavşakta yapılır, yol ortasında değil. Yayalar, bisikletler ve park etmiş araçlar yok; araçlar varınca bina önünde durup kaybolur. İş seçimi hâlâ kuş uçuşu mesafeye bakar. Yol düzenlenince değişen yollardaki araçlar kaybolur ve yeni atama bitene kadar (büyük şehirde telefonda 5–10 sn) yeni araç çıkmaz.
- **Hizmetler (Faz 5):** ambulans, çöp kamyonu, itfaiye aracı gibi hizmet araçları yolda gezmiyor (araçlar ve trafik Faz 6); kapsama şimdilik yol mesafesiyle hesaplanıyor. Elektrik direkleri ve su boruları görünmüyor, yolları izledikleri varsayılıyor. Çöp alanı ve mezarlık boşaltılamıyor; dolunca yenisi gerekir. Yangın binayı anında harabeye çevirir (söndürme yok). Su kirliliği mesafeye bakar, nehrin akış yönü yok. Rüzgâr türbinleri yola bakar, rüzgâr yönü yok; güneş santrali gece de üretir (hava durumu ve gün-gece üretimi Faz 8).
- **Yollar:** serbest el çizimi, tünel, otoyol rampaları/kavşak köprüleri ve çıkmaz sokak dönüş cebi yok; köprüler suya yakın alçak tabliyeli (yükseltilmiş viyadük yok); trafik ışıkları sadece cadde/bulvar kavşaklarında. Kavşak köşeleri çok dar açılarda sadeleşir.
- **Binalar:** Kenney kitinde sadece 5 bina modeli var; çeşitlilik kod ile üretilen binalarla sağlanıyor. Kenney'nin büyük ücretsiz şehir paketleri (kenney.nl) repoya eklenirse kolayca bağlanır. Binalar imarla kendiliğinden gelir; istersen katalogdan elle de yerleştirilir.
- **Doku siteleri:** ambientCG ve Poly Haven bu geliştirme ortamından erişilemedi. Yol ve kaldırım dokuları shader ile üretildi, ek dosya yok. Kenney'nin ücretsiz (CC0) şehir modelleri Faz 3'te binalar için kullanılacak.
- Harita boş başlar; inşa araçları (yol çizme) Faz 2'de gelir. Referans bloklar sadece ışık testi için ve varsayılan kapalı.
- Dinamik çözünürlük GPU darboğazını çözer; FPS düşüklüğü CPU kaynaklıysa (ileride kalabalık simülasyon) çözünürlük düşürmek işe yaramaz — o iş Faz 6'daki simülasyon LOD'unun.
- Ağaçlar düşük poligonlu yer tutucu; gerçek ağaçlar için LOD + uzakta billboard (impostor) gerekecek — 1000'lerce ağaçta bu şart.
- Yağmur/kar ve mevsim renkleri yok (Faz 8); sokak lambaları ve araçlar var.
- Nehir ve göller var (yol ve imar suya girmez), ama arazi yüksekliği yok; şehir alanı düz.
- Tek kayıt yuvası var (otomatik kayıt); birden çok şehir ve bulut kaydı yok.
- Listedeki diğer sistemler (RoadNetwork, ZoneSystem, …) ilgili fazlarda eklenecek; boş taslak dosya bırakılmadı.
- Gölge kalitesi kamera mesafesine göre otomatik ayarlanıyor; çok uzak harita görünümünde gölgeler yumuşar (bilinçli mobil tercih).
