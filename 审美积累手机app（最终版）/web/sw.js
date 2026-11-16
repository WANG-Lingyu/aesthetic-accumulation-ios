// 离线缓存：优先网络、失败回退缓存，保证更新又能离线打开。
const CACHE = 'aesthetic-v1';
const ASSETS = [
  './',
  './index.html',
  './styles.css',
  './app.js',
  './db.js',
  './cutout.js',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png',
  './mediapipe/selfie_segmentation.js',
  './mediapipe/selfie_segmentation.binarypb',
  './mediapipe/selfie_segmentation.tflite',
  './mediapipe/selfie_segmentation_solution_simd_wasm_bin.js',
  './mediapipe/selfie_segmentation_solution_simd_wasm_bin.wasm',
  './mediapipe/selfie_segmentation_solution_wasm_bin.js',
  './mediapipe/selfie_segmentation_solution_wasm_bin.wasm',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // 只缓存同源资源

  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((hit) => hit || caches.match('./index.html')))
  );
});
