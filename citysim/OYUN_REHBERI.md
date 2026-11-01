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
- İmarla kendiliğinden büyüyen binalar para vermez. Yık aracı binanın imarını
  da siler, yerine yeni bina çıkmaz; tekrar bina istersen imarı yeniden boya.

| Yol | Şerit | m başı maliyet |
|---|---|---|
| Sokak | 2 | 10 |
| Tek yön sokak | 2 (tek yön) | 11 |
| Cadde | 4 | 22 |
| Tek yön cadde | 4 (tek yön) | 24 |
| Bulvar | 6 + refüj | 38 |
| Otoyol | 6 + refüj, 100 km/s, kenarında imar yok | 60 |

Cadde ve bulvar kavşaklarında trafik ışığı vardır.

- **Köprü:** yolu suyun üstünden çizebilirsin. Su üstündeki kısım korkuluklu
  köprü olur, metre başına 4 kat pahalıdır. Köprünün iki ucu ve kavşaklar
  karada olmalı.
- **Yükselt:** yol panelinde Yükselt modunu seç, üstten yeni yol tipini seç,
  yola dokun. Yol yerinde değişir (ör. sokak → cadde). Bedel = yeni yolun fiyatı
  − eski yolun iadesi.
- **Dış bağlantılar:** haritanın doğu ve batı kenarından iki otoyol gelir;
  başta hazırdır, yıkılamaz. Şehrini bunlara bağla:
  - Bağlıysan fabrikalar ihracat yapar, dükkânlar normal fiyattan ithal eder,
    göçmenler gelir, otoyolda kamyon ve transit trafik akar.
  - Bağlı değilsen ihracat çok az olur, ithalat pahalıdır, nüfus yavaş artar.

### İmar
Fırça, blok doldurma ve silgi. İmar ücretsizdir. Binalar ancak yola bakan
hücrelerde, talep varsa büyür.

- Düşük / orta / yüksek yoğunluk konut
- Düşük / yüksek yoğunluk ticari
- Ofis, sanayi
- Karma (altta dükkân, üstte konut)

**Binalar zamanla gelişir (seviye 1–5).** Dolu ve mutlu bir ev, ya da birkaç ay
üst üste kâr eden bir dükkân, seviye atlar: kat sayısı artar, kira ve vergi
yükselir. Seviye 5'te yüksek konut 34–46, ofis 32–44 kat olur.

**Yoğunlaşma (ev → apartman → gökdelen).** Seviye 3+ ve hak eden bir bina,
talep varsa yanındaki aynı imarlı binalarla birleşip bir üst imara dönüşür:

- düşük konut → orta konut → yüksek konut (kule)
- düşük ticari → yüksek ticari, karma → yüksek konut

Yeni bina seviye 1'den başlar ve yine 5'e kadar büyür. Yüksek bina yasağı olan
bölgelerde olmaz. Ayarlar → Hileler'den kapatılabilir.

### Binalar
Ev, apartman, kule, dükkân, AVM, ofis, fabrika, atölye, park, koru ve çeşmeli
meydanı katalogdan elle yerleştirebilirsin. Parklar mutluluğu artırır.

### Üretim (hammadde)
Haritada doğal kaynaklar var. Katmanlar → **Kaynaklar** ile görürsün: sarı
verimli toprak, yeşil orman, kahverengi maden, mor petrol.

| Tesis | Kaynak | Fiyat | Açılır |
|---|---|---|---|
| Çiftlik | Verimli toprak | 6.000 | Köy |
| Kereste kampı | Orman | 7.000 | Köy |
| Maden ocağı | Maden (tükenir) | 12.000 | Kasaba |
| Petrol kuyusu | Petrol (tükenir) | 15.000 | Kasaba |

- Tesis işçi çalıştırır ve kaynağın zenginliğine göre hammadde üretir.
  Yerleştirirken zenginlik yüzdesi görünür; kaynak olmayan yere konmaz.
- Fabrikalar önce şehrin hammaddesini kullanır: ithal hammaddeden ucuz olduğu
  için kârları artar. Fazlası otoyoldan ucuza ihraç edilir.
- Az fabrikası olan kasabaya çok tesis kurma: hammadde ucuza dışarı gider,
  tesisler zarar edip küçülür.
- Maden ve petrol rezervi tükenir (binaya uzun bas → kalan rezerv). Tarla ve
  orman kirlilikten etkilenir; sanayiyi onlardan uzak tut.
- Ekonomi → **Üretim** sekmesinde hammadde ve mamul ürün dengesi görünür.

### Park, sahil, liman (yeni)
Tepsideki **çiçek** simgeli düğme. Parklar çevresindeki evlerin mutluluğunu
artırır; büyük parkların etki alanı daha geniştir. Turistik olanlar her ay
**turizm geliri** getirir ama bakım gideri de vardır. Şehir otoyola bağlı
değilse turist az gelir (gelirin yaklaşık üçte biri).

| Yapı | Etki alanı | Turizm/ay | Bakım/ay | Açılış |
|---|---|---|---|---|
| Oyun parkı | 170 m | – | 60 | Baştan |
| Heykelli park | 200 m | 250 | 90 | Köy |
| Futbol sahası | 240 m | 150 | 160 | Köy |
| Botanik bahçesi (cam kubbe) | 260 m | 900 | 240 | Kasaba |
| Hayvanat bahçesi (fil, zürafa, aslan, zebra) | 320 m | 3.200 | 700 | İlçe |
| Lunapark (dönme dolap, hız treni, atlıkarınca) | 340 m | 4.800 | 1.000 | İlçe |

**Deniz ve sahil kenti:** haritanın güneyinde dalgalı bir sahil şeridi ve
geniş bir kumsal var (başlangıç alanının hemen güneyi; Kasaba olunca tamamı
açılır). Denize yakın evler (220 m) **deniz manzarası** sayesinde daha mutlu
olur ve daha çok tercih edilir. Sahil yapıları ancak kıyıya kurulur:

| Yapı | Ne yapar | Turizm/ay | Açılış |
|---|---|---|---|
| Plaj | Şemsiyeler, şezlonglar, cankurtaran kulesi, voleybol filesi | 1.400 | Baştan |
| Sahil kafesi | Küçük ticari bina, terasta masalar | – | Baştan |
| İskele | Denize uzanan ahşap iskele, ucunda köşk | 1.100 | Köy |
| Deniz feneri | Kırmızı-beyaz kule, gece yanıp sönen ışık | 700 | Köy |
| Marina | Kulüp binası, denize uzanan iskeleler ve tekneler | 2.400 | Kasaba |
| Sahil oteli | Balkonlu yüksek otel, havuz; ticari bina | 1.500 | Kasaba |

**Liman ve havalimanı** (aynı menüde):

| Yapı | Ne yapar | Turizm/ay | Bakım/ay | Açılış |
|---|---|---|---|---|
| Liman | Kıyıya kurulur: rıhtım, 2 konteyner vinci, yanaşmış gemi. **Deniz ticareti:** otoyola bağlı olmasan da ticaret tam çalışır, ihracat fiyatı %15 artar, ithalat %15 ucuzlar | 600 | 1.500 | İlçe |
| Havalimanı | Terminal, kule, uçaklar. Arkasında 45 × 320 m boş alan ister (yol, bina, su olmasın); pist buraya çizilir. **Göç %25 artar**, otoyolsuz da turist gelir | 4.000 | 3.000 | Büyük Şehir |

Ekonomi → Bütçe'de **Turizm** geliri ve **Park bakımı** gideri ayrı satır
olarak görünür.

### Ürün çeşitleri
Her fabrika tek bir ürün yapar ve kendi hammaddesini kullanır:

| Ürün | Hammadde | İhracat fiyatı |
|---|---|---|
| Gıda | Çiftlik (verimli toprak) | ×1,00 |
| Kereste ürünleri | Kereste kampı (orman) | ×0,95 |
| Metal eşya | Maden | ×1,15 |
| Yakıt | Petrol kuyusu | ×1,25 |

Yeni fabrika, şehirde en çok artan hammaddeye göre ürününü seçer: tarım
kasabasında gıda fabrikaları, maden kasabasında metal atölyeleri açılır.
Kendi hammaddesi şehirde yoksa ithal eder (daha pahalı). Ekonomi → Üretim
sekmesinde her ürünün miktarı ve hammaddesinin yüzde kaçının yerelden
geldiği görünür.

### Hizmetler ve Altyapı
Yerleştirirken kapsama haritası açılır. Hizmet binalarının yol kenarında kendi
renginde bir tabelası var (elektrik sarı, su mavi, sağlık kırmızı, eğitim mor,
polis lacivert, itfaiye turuncu, çöp yeşil, defin gri); evlerden kolayca ayrılır.

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
- **Metro (Büyük Şehir, 10.000 nüfus):** istasyonlar herhangi bir yolun
  kenarına konur (aralarında en az 250 m). Tünel istasyonlar arasında yerin
  altından, nehrin altından bile geçer; yollara bağlı değildir. Trenler ilk
  istasyondan sonuncusuna gidip gelir, bu yüzden döngü gerekmez.
  - Hızlı (22 m/sn) ve çok yolcu taşır (tren başına 4.500 yolcu/gün).
    İnsanlar istasyona 650 m'ye kadar yürür.
  - Pahalı: hat 20.000 + istasyon başına 12.000 + tünelin metresi 40. Tren
    başına aylık bakım 1.600.
  - Trenler yerin altında olduğu için görünmez. Tüneller Katmanlar → Toplu
    taşıma'da kalın renkli çizgi olarak görünür. Sokakta cam korkuluklu,
    renkli tabelalı metro girişleri durur.
- **Tren (Şehir, 5.000 nüfus):** istasyonlar yol üstüne konur (en az 400 m
  arayla). Hat 8 m yükseklikte **viyadük** üzerinden gider; ayaklar yollara ve
  binalara basmaz. Trenler (3 vagon) gidip gelir ve görünür.
  - En hızlı (30 m/sn) ve en çok yolcu taşıyan araç (tren başına 6.000/gün).
  - Pahalı: hat 30.000 + istasyon 15.000 + viyadük metresi 55; tren başına
    aylık 2.400.
  - **Şehirlerarası hat:** ilk ya da son istasyon açık haritanın kenarına
    260 m'den yakınsa viyadük ufka kadar uzar. Bu durumda şehir otoyola bağlı
    olmasa bile göç ve turist tam gelir.
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

### Para nasıl kazanılır

Muhasebe mantığı: kasa = aylık gelirler − aylık giderler.

- **En büyük gelir vergidir.** Hane sayısı ve şirket kârı arttıkça vergi artar.
  Seviye atlamış binalar daha çok kira ve vergi öder; bu yüzden **mutlu ve
  dolu** mahalle en kârlı varlıktır.
- **Ücretler:** su ve elektrik ücreti, otobüs/tramvay bileti, otopark.
- **Ticaret:** şehirde üretilen mal önce şehirde satılır, fazlası otoyoldan
  ihraç edilir. Otoyola bağlı değilsen ticaret zayıflar.
- **Kilometre taşı ödülleri** tek seferlik büyük para verir.
- **Giderler:** yol bakımı, hizmet binaları, toplu taşıma, kredi taksidi.
  Kullanılmayan hizmetin bütçesini kısmak hızlı tasarruftur.

---

## 6. Kilometre taşları (ilerleme)

| Unvan | Nüfus | Ödül | Açılanlar |
|---|---|---|---|
| Mezra | 0 | — | Sokaklar, düşük konut/ticari, sanayi, temel hizmetler; inşa alanı 2,4 km |
| Köy | 300 | 5.000 | Caddeler, orta konut, karma, fabrika, doğalgaz/güneş, lise, **otobüs** |
| Kasaba | 1.000 | 15.000 | Ofis, hastane, arıtma, çöp yakma, meydan, **bölgeler**; alan 3,2 km |
| İlçe | 2.500 | 25.000 | **Bulvar**, yüksek ticari, AVM, krematoryum, **tramvay** |
| Şehir | 5.000 | 40.000 | Yüksek konut, kule, üniversite, tren; **tüm harita (4 km)** |
| Büyük Şehir | 10.000 | 60.000 | Metro, havalimanı, daha yüksek kredi limiti |
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

### Yayalar ve park etmiş arabalar
Kaldırımlarda insanlar yürür. Bir sokakta ne kadar çok kişi yaşar ve
çalışırsa o kadar kalabalık olur; gece sayıları azalır. Oyun durunca onlar
da durur. Sayı tavanı kaliteye göre: Düşük 400, Orta 1.200, Yüksek 2.500.
İçinde oturulan evlerin çoğunun ön bahçesinde, yola paralel park etmiş bir
araba durur.

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
- **Hileler (serbest mod):** Ayarlar → Kayıt satırındaki **Hileler** düğmesi.
  - **+100.000 / +1.000.000 / +10.000.000:** kasaya anında para (bütçede
    görünmez).
  - **Tüm kilitleri aç:** bütün yollar, binalar ve harita alanı açılır.
  - **Sınırsız para:** kasa 1 milyonun altına düşünce 2 milyona tamamlanır.
  - **Hızlı büyüme:** 3 kat göç, büyüme ve seviye atlama; yoğunlaşma talep
    beklemez.
  - **Kendiliğinden yoğunlaşma:** ev → apartman → gökdelen (varsayılan açık).
  Seçimler `settings.cfg` içinde saklanır, istediğin zaman kapatırsın.

---

## 12. İlk yarım saat için plan (ipuçları)

1. **Otoyola bağlan.** Haritanın doğu veya batı kenarından gelen otoyolun ucuna
   bir sokak/cadde çek; ticaret ve göç buradan gelir.
2. **Su ve elektrik önce gelir.** Nehre yakın bir yere sokak çek. Kenarına su
   pompası, uzağına (akıntı yönünün aşağısına) atık su çıkışı koy. Bir rüzgâr
   türbini veya kömür santrali yap.
3. **Küçük başla.** 3–4 sokaklık bir ızgara yap. Düşük konut, biraz düşük
   ticari, konuttan uzağa sanayi boya (kirlilik ve kamyon gürültüsü).
4. **RCI çubuklarına bak.** Hangi çubuk yüksekse o imardan ekle.
5. **Hizmetleri ihtiyaç oldukça ekle.** Sağlık ocağı, ilkokul, karakol, itfaiye
   ve çöp alanı ilk 300–1.000 nüfusta yeterli. Katmanlardan kapsamaya bak.
6. **Bütçeyi izle.** Ekonomi → Bütçe'de net eksiye düşerse vergiyi 1–2 puan
   artır, kullanılmayan hizmetin bütçesini kıs. Gerekirse kısa süreli kredi al.
7. **Köy olunca** caddeleri ana aks yap, otobüs hattı aç. **Kasaba olunca**
   konut mahallesini bölge olarak çiz ve ağır araç yasağı koy: kamyonlar
   evlerin arasından geçmesin.
8. **Trafik sıkışırsa** paralel yol, tek yön çiftleri veya toplu taşıma kullan.
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
  (177 kontrol).
- **APK:** her push'ta GitHub Actions derler, Releases → `citysim-latest`.
- Ayrıntılı faz notları, kabul kriterleri ve bilinen eksikler: `README.md`.

## 14. Bilinen sınırlar (kısaca)

- Karayolu tüneli, otoyol rampaları, banliyö treni ve liman yok. Metro trenleri
  yerin altında olduğu için çizilmiyor.
- Yayalar süs amaçlı: yürüyüş yolları gerçek yolculuklardan değil sokağın
  nüfusundan gelir. Bisiklet yok.
- Doku ve sesler sentetik. Geliştirme ortamı ücretsiz asset sitelerine
  erişemedi; aynı dosya adlarıyla gerçek asset'lerle değiştirilebilir.
- Tek dil dosyası: Türkçe ve İngilizce metinler hazır, arayüz şimdilik Türkçe.
