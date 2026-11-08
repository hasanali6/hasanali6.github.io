# Bilgisayarda geliştirme (Windows)

Bilgisayarda Godot editöründe değiştir, GitHub Desktop ile gönder: ~10 dakika sonra
**aynı linkten** yeni APK (ve Windows sürümü) iner. Claude da aynı dalda çalışmaya devam
eder; ikimizin değişiklikleri aynı APK'da birleşir.

- APK: https://github.com/hasanali6/hasanali6.github.io/releases/download/citysim-latest/SehirSim.apk
- Windows: https://github.com/hasanali6/hasanali6.github.io/releases/download/citysim-latest/SehirSim-Windows.zip

## 1. Bir kez kurulum (~10 dakika)

1. **GitHub Desktop**'ı kur: https://desktop.github.com → GitHub hesabınla giriş yap.
2. *File → Clone repository* → `hasanali6/hasanali6.github.io` → *Clone*.
3. Üstte **Current branch** → **`ccr-36f23ef9-qlqpvv`** seç. Önemli: APK bu daldan derleniyor.
4. Klasörde `citysim\pc\kurulum.bat` dosyasına çift tıkla. Godot 4.7.2'yi indirip
   (yaklaşık 70 MB) projeyi açar. İlk açılışta dokular 1–2 dakika yüklenir.
   - Windows "korumalı" uyarısı verirse *Ek bilgi → Yine de çalıştır*.
   - Başka bir Godot sürümü kullanma: dosya biçimini değiştirip derlemeyi bozabilir.

## 2. Her çalışmada

1. GitHub Desktop → **Fetch origin**, sonra **Pull origin**. Claude'un son değişikliklerini alırsın.
   Bunu her işe başlamadan önce yap.
2. `citysim\pc\gelistir.bat` → editör açılır. Değiştir, **F5** ile dene.
   (`oyna.bat` editörsüz direkt oyunu açar.)
3. GitHub Desktop'ta sol altta *Summary*'ye kısa bir not yaz (ör. "Okul fiyatı düşürüldü")
   → **Commit to ccr-36f23ef9-qlqpvv** → **Push origin**.
4. ~10 dakika sonra APK linkinden yeni sürümü indir.
   - Derleme durumu: GitHub'da repo → **Actions**. Yeşil tamam demek, kırmızıysa Claude'a yaz.

## Kontroller (bilgisayarda)

| Fare | İş |
|---|---|
| Sol tık sürükle | Kaydır / yol çiz / imar boya |
| Sağ tık sürükle | Döndür ve eğ |
| Tekerlek | Zoom |
| Sol tık basılı tut | Konum / bina bilgisi |

## Nerede ne var

| Klasör | İçerik |
|---|---|
| `data/*.json` | **Bütün denge sayıları**: fiyatlar, vergiler, talep (`economy.json`), imar ve bina boyutları (`zones.json`, `catalog.json`), hizmetler (`services.json`), suç, afet, görevler (`life.json`). Kod bilmeden buradan oynayabilirsin. |
| `scripts/` | Oyun kodu (GDScript) |
| `locale/strings.csv` | Ekrandaki bütün yazılar (Türkçe / İngilizce) |
| `tests/run_tests.gd` | Otomatik testler. CI her gönderimde çalıştırır, kırılırsa APK çıkmaz. |
| `OYUN_REHBERI.md` | Oyunun nasıl oynandığı |

Godot'nun oluşturduğu `.uid` dosyalarını da commit'le. `pc\godot\` klasörü (indirilen editör)
zaten gönderilmez.

## Çakışmayı önlemek (ikimiz aynı dalda)

- İşe başlamadan **önce Pull**, bitirince **hemen Push**. Değişikliği günlerce bekletme.
- Aynı dosyada aynı anda çalışmayalım. Büyük bir şeye başlarken Claude'a hangi dosyayla
  uğraştığını yaz.
- Claude her göndermeden önce senin değişikliklerini çeker; seninkiler ezilmez.
- GitHub Desktop "conflict" derse hiçbir şeyi silme: **Abort merge** de ve Claude'a hangi
  dosya olduğunu yaz, birlikte çözeriz.

## Kayıtlar

Bilgisayardaki şehir ayrı tutulur (`%APPDATA%\Godot\app_userdata\Şehir Simülasyonu\saves`).
Telefondaki şehir bilgisayara kendiliğinden gelmez.
