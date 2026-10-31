# Şehir Simülasyonu — Oyun Rehberi

Android için yatay ekranda oynanan bir şehir kurma oyunu. Cities: Skylines 2'nin
mantığından ilham alır: sen yolu, imarı ve hizmetleri kurarsın, şehir kendi
kendine yaşar. İnsanlar taşınır, işe gider, alışveriş yapar, vergi öder. Memnun
değillerse şehirden giderler.

---

## 1. Oyunun temel döngüsü

Şehri bir şirket bilançosu gibi düşün:

1. **Yatırım:** yol yaparsın, üstüne imar boyarsın (konut, ticari, sanayi…).
2. **Büyüme:** talep varsa imarlı yere binalar kendiliğinden yükselir. Evlere
   haneler, iş yerlerine şirketler gelir.
3. **Gelir:** haneler ve şirketler vergi öder; su, elektrik, bilet ve otopark
   ücretleri de kasaya girer.
4. **Gider:** yol bakımı, hizmet binaları, toplu taşıma, kredi taksidi.
5. **Memnuniyet:** sağlık, eğitim, güvenlik, kirlilik, gürültü, park, vergi ve
   işe gidiş süresi mutluluğu belirler. Mutlu şehir büyür, mutsuz şehir boşalır.

Kural basit: **gelir giderden fazla olsun, insanlar mutlu olsun.**

**Zaman:** bir oyun günü (gece + gündüz) = bir ay. 1x hızda bir gün 6 gerçek
dakika sürer. Aylık bütçe her gün sonunda kapanır. Hız: Dur / 1x / 2x / 3x.

---

## 2. Kontroller

| Hareket | Ne yapar |
|---|---|
| Tek parmakla sürükle | Haritayı kaydırır (inşa modunda çizer/boyar) |
| İki parmakla birlikte kaydır | Haritayı kaydırır (inşa modunda da çalışır) |
| İki parmakla sıkıştır | Yakınlaştırır / uzaklaştırır |
| İki parmakla belirgin döndür | Kamerayı çevirir (yakınlaştırırken kendiliğinden dönmez) |
| Soldaki ⟲ ⟳ düğmeleri | Kamerayı 45° çevirir |
| Soldaki ˄ ˅ düğmeleri | Bakış açısını yükseltir / alçaltır |
| Uzun bas | Binada bina bilgisi, yolda yol bilgisi, boş arazide konum |
| Geri tuşu | Açık paneli kapatır; iki kez basınca çıkar |

**İnşa / Kamera düğmesi:** bir araç açıkken (yol, imar, bina, ulaşım, bölge,
yık) sağda büyük bir düğme çıkar.
- Turuncu kalem = **İnşa**: tek parmak çizer.
- Dokununca mavi = **Kamera** olur: tek parmak haritayı kaydırır, araç ve
  seçimin açık kalır.
- Tekrar dokununca inşaya dönersin. Paneli kapatınca kendiliğinden İnşa'ya
  döner.

Kamera uzaktayken harita görünümüne, yakındayken sokak seviyesine yumuşakça
geçer.

## 3. Ekran

- **Sol üst:** nüfus, mutluluk, RCI talep çubukları (K = konut, T = ticari,
  O = ofis, S = sanayi).
- **Üst orta:** saat, tarih, hava ikonu, mevsim ve hız düğmeleri.
- **Sağ üst:** para ve aylık net (yeşil artı, kırmızı eksi), ayarlar.
- **Sol:** Katmanlar (bilgi haritaları) ve Ekonomi.
- **Sağ alt:** büyük **İnşa Et** düğmesi ve kategori menüsü.

---

## 4. İnşa Et menüsü

### Yollar
Düz veya eğri çizim. Kesişen yollar kendiliğinden kavşak olur. Çizerken maliyet
görünür.

Düz çizimde yol 15°'lik adımlarla ve 8 m'lik boylarla ilerler. Açı, başladığın
yola göre ölçülür; parmağın titrese de yol ya o yolun düz devamı olur ya da
tam dik keser. Uç nokta yakındaki bir kavşağa veya yola ancak çizdiğin yön
bozulmuyorsa yapışır. Serbest açı veya kavis için eğri modunu kullan.

### Yık
Menüdeki kırmızı **Yık** düğmesi (yol panelindeki yıkma modu da aynı işi
yapar). Bir binaya ya da yola dokun: kırmızı işaretlenir, parmağını kaldırınca
yıkılır.
- Yollar fiyatının %75'ini geri verir.
- Elle konan binalar ve hizmet binaları fiyatının yarısını geri verir.
- İmarla kendiliğinden büyüyen binalar para vermez. İmar duruyorsa yerine
  zamanla yenisi gelir; tamamen boşaltmak için imarı da silgiyle sil.

| Yol | Şerit | m başı maliyet |
|---|---|---|
| Sokak | 2 | 10 |
| Tek yön sokak | 2 (tek yön) | 11 |
| Cadde | 4 | 22 |
| Tek yön cadde | 4 (tek yön) | 24 |
| Bulvar | 6 + refüj | 38 |

Cadde ve bulvar kavşaklarında trafik ışığı vardır. Yollar su üstünden geçemez
(köprü yok).

### İmar
Fırça, blok doldurma ve silgi. İmar ücretsizdir. Binalar ancak yola bakan
hücrelerde, talep varsa büyür.

- Düşük / orta / yüksek yoğunluk konut
- Düşük / yüksek yoğunluk ticari
- Ofis, sanayi
- Karma (altta dükkân, üstte konut)

### Binalar
Ev, apartman, kule, dükkân, AVM, ofis, fabrika, atölye, park, koru ve çeşmeli
meydanı katalogdan elle yerleştirebilirsin. Parklar mutluluğu artırır.

### Hizmetler ve Altyapı
Yerleştirirken kapsama haritası açılır.

| Hizmet | Bina (maliyet / aylık bakım) |
|---|---|
| Elektrik | Kömür (30.000 / 1.400), doğalgaz (38.000 / 1.600), rüzgâr (7.000 / 160), güneş (20.000 / 320) |
| Su | Su pompası (9.000 / 420), nehir veya göl kenarına |
| Kanalizasyon | Atık su çıkışı (5.000 / 220) suyu kirletir, arıtma tesisi (26.000 / 950) temizler |
| Sağlık | Sağlık ocağı (9.000 / 650), hastane (32.000 / 2.200) |
| Eğitim | İlkokul (12.000), lise (22.000), üniversite (52.000) |
| Güvenlik | Karakol (11.000), itfaiye (11.000) |
| Çöp | Depolama alanı (9.000, dolar), yakma tesisi (30.000) |
| Defin | Mezarlık (7.000, dolar), krematoryum (16.000) |

Elektrik ve su olmayan binada uyarı ikonu çıkar. Bu durum uzun sürerse bina
terk edilir. Kirli suyun aşağısına pompa koyma.

### Ulaşım (toplu taşıma)
- **Otobüs:** yola dokunarak durak koy, "Hattı aç".
- **Tramvay:** sadece cadde ve bulvarlarda; asfalta gömülü ray çizilir.
- Araçlar yolun ortasında U dönüşü yapamaz. Hat bir yapı adasını dolaşan bir
  döngü olmalı; çıkmaz sokağa hat açılmaz.
- Her hatta araç sayısı (−/+), yolcu/gün, doluluk ve sefer aralığı görünür.
  Bilet fiyatı bütün hatlarda ortaktır.
- İnsanlar arabayı (yol süresi + park yeri + otopark ücreti) toplu taşımayla
  (yürüme + bekleme + yolculuk + bilet) karşılaştırır. Ucuz olanı seçerler.
  Hat doluysa fazlası arabaya döner.

### Bölgeler ve politikalar
Haritaya köşe köşe dokunarak bölge çiz, ilk köşeye dokununca kapanır. Adını
panelden değiştir.

| Politika | Etki |
|---|---|
| Ağır araç yasağı | Kamyonlar bölgeden geçmemeye çalışır, gürültü azalır (+2 mutluluk) |
| Yüksek bina yasağı | Yeni ve büyüyen binalar en fazla 4 kat (+1) |
| Geri dönüşüm | Çöp %35 azalır, kişi başı aylık küçük maliyet (+1) |
| Ücretli otopark | Arabayla gelen ücret öder, şehre gelir; daha çok kişi otobüse biner (−1) |

---

## 5. Ekonomi paneli

| Sekme | İçerik |
|---|---|
| **Bütçe** | Geçen ayın gelir ve giderleri kalem kalem, aylık net |
| **Vergiler** | Konut (eğitim düzeyine göre ayrı), ticari, ofis, sanayi; −%10 ile +%30 arası. Yüksek vergi geliri artırır ama talebi ve mutluluğu düşürür |
| **Hizmetler** | Her hizmetin bütçesi %50–150 (verim ve bakım birlikte değişir); elektrik ve su ücreti |
| **Kredi** | Tek, ayarlanabilir kredi. Limit kilometre taşlarıyla artar, faiz kullanılan orana göre değişir, 24 ayda geri ödenir |
| **İlerleme** | Unvan, sonraki kilometre taşına ilerleme çubuğu, ödül ve açılacaklar |

Başta 60.000 para ile başlarsın. Küçük şehre azalan bir devlet desteği ve
işsizlik yardımı gelir.

---

## 6. Kilometre taşları (ilerleme)

| Unvan | Nüfus | Ödül | Açılanlar |
|---|---|---|---|
| Mezra | 0 | — | Sokaklar, düşük konut/ticari, sanayi, temel hizmetler; inşa alanı 2,4 km |
| Köy | 300 | 5.000 | Caddeler, orta konut, karma, fabrika, doğalgaz/güneş, lise, **otobüs** |
| Kasaba | 1.000 | 15.000 | Ofis, hastane, arıtma, çöp yakma, meydan, **bölgeler**; alan 3,2 km |
| İlçe | 2.500 | 25.000 | **Bulvar**, yüksek ticari, AVM, krematoryum, **tramvay** |
| Şehir | 5.000 | 40.000 | Yüksek konut, kule, üniversite; **tüm harita (4 km)** |
| Büyük Şehir | 10.000 | 60.000 | Daha yüksek kredi limiti |
| Metropol | 25.000 | 100.000 | Daha yüksek kredi limiti |
| Megakent | 50.000 | 200.000 | En yüksek kredi limiti |

Kilitli düğmeler gri görünür. Dokununca hangi unvanda açılacağı yazar.

---

## 7. Katmanlar (bilgi haritaları)

Elektrik, su, sağlık, eğitim, polis, itfaiye, çöp, defin, kirlilik, mutluluk,
trafik ve toplu taşıma. Zemin griye döner, hücreler ve binalar renklenir:
yeşil iyi, sarı orta, kırmızı kötü. Trafik katmanında yollar doluluğa göre,
evler işe gidiş süresine göre boyanır. Toplu taşıma katmanında durağa yakın
sokaklar yeşildir ve hatlar renkli şerit olarak görünür.

---

## 8. Trafik

- Herkes ev → iş → ev yapar. Haneler alışverişe gider, sanayiden dükkâna kamyon
  gider, hizmet binaları evlere araç gönderir (çöp kamyonu, polis, ambulans,
  itfaiye, cenaze aracı).
- Rotalar sıkışıklığa göre seçilir. Dolu yoldan kaçan sürücüler başka yol bulur;
  paralel bir cadde açmak trafiği böler.
- Yola uzun basınca şerit, hız sınırı, günlük araç, doluluk ve ortalama hız
  görünür.
- İşe gidiş 15 dakikayı geçince mutluluk düşer. Yoğun yol kenarındaki evlere
  gürültü cezası gelir.
- Yağmurda araçlar %12, karda %20 yavaşlar ve yollar daha çabuk tıkanır.

---

## 9. Hava ve mevsimler

- **Mevsimler takvimden gelir:** Mart–Mayıs ilkbahar, Haziran–Ağustos yaz,
  Eylül–Kasım sonbahar, Aralık–Şubat kış. Her mevsim 3 oyun günü sürer.
- **Hava:** açık, bulutlu, yağmurlu, karlı (kar sadece kışın).
  - Yağmurda yollar ıslanıp parlar, su birikintileri olur, sonra kurur.
  - Kar zemini, kaldırımı, çatıları ve ağaçları beyazlatır, yavaş erir.
  - Sonbaharda ağaçlar sararır.
- **Oyuna etkisi:** bulutta güneş santrali az, rüzgârda türbin biraz fazla
  üretir; trafik yavaşlar.
- Ayarlar → "Hava durumu" ile yağmur ve kar kapatılabilir.

---

## 10. Kayıt

- Ayarlar → **Kayıtlar:** otomatik kayıt ve 3 yuva. Her yuvada tarih, unvan,
  nüfus ve para görünür.
- Otomatik kayıt her ay ve uygulama arka plana geçince yapılır. Açılışta en son
  otomatik kayıt yüklenir.
- Yüklemek için "Yükle"ye iki kez dokun. Kaydedilmemiş ilerleme gider.

---

## 11. Ayarlar ve performans

- **Kalite: Düşük / Orta / Yüksek.** Gölge, çizim mesafesi, araç sayısı tavanı
  (300 / 800 / 1.500), yağmur-kar parçacıkları ve doku detayı değişir.
- Ekran yenileme hızına göre FPS kilidi otomatik ayarlanır. GPU yetişemezse 3B
  çözünürlük kendiliğinden düşer.
- Sol alttaki satır FPS, GPU ve CPU süresini gösterir.
- **Ses:** Müzik / Efekt / Ortam kaydırıcıları.
- **Ortam sesleri:** alçakta kuşlar ve trafik, gece cırcır böcekleri, yağmur,
  yükseklerde rüzgâr.

---

## 12. İlk yarım saat için plan (ipuçları)

1. **Su ve elektrik önce gelir.** Nehre yakın bir yere sokak çek. Kenarına su
   pompası, uzağına (akıntı yönünün aşağısına) atık su çıkışı koy. Bir rüzgâr
   türbini veya kömür santrali yap.
2. **Küçük başla.** 3–4 sokaklık bir ızgara yap. Düşük konut, biraz düşük
   ticari, konuttan uzağa sanayi boya (kirlilik ve kamyon gürültüsü).
3. **RCI çubuklarına bak.** Hangi çubuk yüksekse o imardan ekle.
4. **Hizmetleri ihtiyaç oldukça ekle.** Sağlık ocağı, ilkokul, karakol, itfaiye
   ve çöp alanı ilk 300–1.000 nüfusta yeterli. Katmanlardan kapsamaya bak.
5. **Bütçeyi izle.** Ekonomi → Bütçe'de net eksiye düşerse vergiyi 1–2 puan
   artır, kullanılmayan hizmetin bütçesini kıs. Gerekirse kısa süreli kredi al.
6. **Köy olunca** caddeleri ana aks yap, otobüs hattı aç. **Kasaba olunca**
   konut mahallesini bölge olarak çiz ve ağır araç yasağı koy: kamyonlar
   evlerin arasından geçmesin.
7. **Trafik sıkışırsa** paralel yol, tek yön çiftleri veya toplu taşıma kullan.
   Çok kavşaklı tek bir ana yola her şeyi bağlama.

---

## 13. Teknik özet

- **Motor:** Godot 4.7.2, Mobile renderer (Vulkan). Ayrıca OpenGL sürümü
  (`SehirSim-GL.apk`) var.
- **Kod:** GDScript.
  - Simülasyon (veri) ile görsel (Node) ayrı.
  - Sistemler birbirini tanımaz, EventBus sinyalleriyle konuşur.
  - Bütün denge sayıları `data/*.json` içinde.
- **Simülasyon:** sabit 10 Hz tick. Trafik ataması arka plan iş parçacığında
  çalışır.
- **Araç gösterimi:** araçlar ekran kartında hareket eder (MultiMesh). Yakındaki
  araçlar çizilir, uzaktakiler veri olarak, geri kalanı istatistik olarak
  hesaplanır (simülasyon LOD).
- **Testler:** `godot --headless --path citysim -s res://tests/run_tests.gd`
  (164 kontrol).
- **APK:** her push'ta GitHub Actions derler, Releases → `citysim-latest`.
- Ayrıntılı faz notları, kabul kriterleri ve bilinen eksikler: `README.md`.

## 14. Bilinen sınırlar (kısaca)

- Otoyol, köprü/tünel, metro, tren, liman ve şehir dışı bağlantılar yok.
- Üretim zinciri (hammadde → işlenmiş ürün) basit tutuldu; sanayi doğrudan
  dükkânlara mal gönderir.
- Yayalar, bisikletler ve park etmiş araçlar görünmüyor; sayılar arka planda
  hesaplanıyor.
- Doku ve sesler sentetik. Geliştirme ortamı ücretsiz asset sitelerine
  erişemedi; aynı dosya adlarıyla gerçek asset'lerle değiştirilebilir.
- Tek dil dosyası: Türkçe ve İngilizce metinler hazır, arayüz şimdilik Türkçe.
