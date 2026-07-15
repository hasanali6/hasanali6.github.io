# Denge — Yayınlama ve APK Kurulumu

Mantık şu: uygulamayı bir adrese koyuyoruz, APK sadece o adresi açan ince bir kabuk oluyor.
Böylece her değişiklikte APK'yı yeniden kurmuyorsun — tek dosyayı güncelliyorsun, uygulama kendi alıyor.

---

## 1. Adım — Siteyi yayına al (GitHub Pages, ücretsiz)

1. GitHub'da hesap aç (varsa geç).
2. **Yeni repo oluştur.** İsmi tam olarak şu olsun:
   `kullaniciadin.github.io`
   (örnek: kullanıcı adın `hasanali` ise repo adı `hasanali.github.io`)
   Repo **Public** olacak. → *Neden bu isim: sitenin adres kökünde olması gerekiyor, yoksa 3. adımdaki imza doğrulaması çalışmıyor.*
3. Bu klasördeki şu dosyaları repoya yükle (Add file → Upload files):
   - `index.html`
   - `manifest.json`
   - `sw.js`
   - `icon-192.png`
   - `icon-512.png`
   - `icon-maskable.png`
   - `apple-touch-icon.png`
4. Settings → Pages → Source: **Deploy from a branch**, Branch: **main / (root)** → Save.
5. 1-2 dakika bekle. Sitem hazır: `https://kullaniciadin.github.io/`

> Repo public ama içinde gizli bir şey yok — sadece uygulamanın kodu.
> **Senin finansal verilerin siteye gitmiyor**, telefonun içinde kalıyor.

---

## 2. Adım — Telefona kur (APK'sız, 10 saniye)

Chrome'da adresi aç → sağ üst ⋮ → **Uygulamayı yükle** / **Ana ekrana ekle**.

Bu kadar. İkonuyla, tam ekran, çevrimdışı çalışır. Test için bu yeterli.
APK'ya gerçekten ihtiyacın olduğunu düşünüyorsan 3. adıma geç.

---

## 3. Adım — Gerçek APK (PWABuilder ile, derleme yok)

1. `https://www.pwabuilder.com` adresine git.
2. Site adresini yapıştır → **Start**.
3. Android kutusunda **Package For Stores** → paket seçenekleri:
   - Package ID: `com.hasanali.denge` gibi bir şey yaz — **bunu bir daha asla değiştirme**.
   - "Signing key": **New** seç.
4. İnen zip'in içinde:
   - `app-release-signed.apk` → telefona at, kur ("bilinmeyen kaynak" izni ister, ver).
   - `signing.keystore` + `signing-key-info.txt` → **bunları kaybetme.** İleride yeni APK üretirsen aynı anahtarı kullanman lazım, yoksa Android üstüne kurmayı reddeder ve verilerin silinir.
   - `assetlinks.json` → repoya `.well-known/assetlinks.json` yoluna yükle
     (GitHub'da Add file → Create new file → isim kutusuna `.well-known/assetlinks.json` yaz, içeriği yapıştır).
     Bunu yapmazsan uygulamanın üstünde çirkin bir adres çubuğu görünür.

---

## Değişiklikleri nasıl göndereceğiz?

APK'ya bir daha dokunmuyorsun. Döngü şu:

1. Ben yeni `index.html` veriyorum.
2. GitHub'da repoya gir → `index.html` → kalem ikonu → içeriği değiştir → Commit.
   (Ya da eski dosyayı silip yenisini upload et.)
3. `sw.js` içindeki `const CACHE = "denge-v1";` satırını `denge-v2` yap. Sonraki güncellemede `v3`...
   *Neden: telefon eski sürümü önbellekte tutuyor; numarayı artırmak "bu eskidi, yenisini al" demek.*
4. Telefonda uygulamayı kapat-aç. Yeni sürüm gelir. Verilerin yerinde kalır.

---

## Yedek al, sonra rahat et

Ciddi veri girmeye başlamadan önce: Ayarlar → **Yedek al** → JSON dosyası.
Bir terslik olursa Ayarlar → **Yedekten geri yükle**.
