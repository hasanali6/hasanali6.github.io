/* Denge — Service Worker
   Strateji:
   - HTML (navigasyon): önce ağ, olmazsa önbellek  → güncelleme anında gelir, internet yoksa çalışmaya devam eder
   - Diğer dosyalar (ikon, manifest): önce önbellek, arkada tazele
   Yeni sürüm yayınlarken CACHE değerindeki numarayı artırman yeterli. */

const CACHE = "denge-v1";
const ASSETS = [
  "./",
  "./index.html",
  "./manifest.json",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable.png",
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET" || !req.url.startsWith(self.location.origin)) return;

  // Uygulamanın kendisi: önce ağ → her açılışta en güncel sürüm
  if (req.mode === "navigate" || req.destination === "document") {
    e.respondWith(
      fetch(req)
        .then(res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put("./index.html", copy)); return res; })
        .catch(() => caches.match("./index.html").then(r => r || caches.match("./")))
    );
    return;
  }

  // Statik dosyalar: önce önbellek, arkada tazele
  e.respondWith(
    caches.match(req).then(hit => {
      const net = fetch(req).then(res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); return res; }).catch(() => hit);
      return hit || net;
    })
  );
});
