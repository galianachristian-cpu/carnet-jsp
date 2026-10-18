// Carnet JSP : service worker pour une ouverture instantanée.
// - Pages du carnet : la copie gardée sur l'appareil s'affiche tout de suite, la version en ligne
//   est téléchargée en arrière-plan ; si elle a changé, la page propose « Actualiser ».
// - Bibliothèques des CDN (PDF, Excel, icônes, polices) : gardées sur l'appareil.
// - Données (Supabase) : jamais mises en cache, toujours demandées au serveur.
const CACHE = 'carnet-jsp-v1';
const CDN = ['cdnjs.cloudflare.com', 'cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];
const BASE = new URL('./', self.location).pathname; // « /carnet-jsp/ »

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.add(BASE + 'index.html')).catch(() => {}));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k.startsWith('carnet-jsp-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

// « /carnet-jsp/ » et « /carnet-jsp/index.html?x » partagent la même copie
function clePage(url) {
  const p = url.pathname.endsWith('/') ? url.pathname + 'index.html' : url.pathname;
  return new Request(url.origin + p);
}
const signature = r => r && (r.headers.get('etag') || r.headers.get('last-modified') || r.headers.get('content-length'));

async function pageDuCarnet(e, url) {
  const cache = await caches.open(CACHE), cle = clePage(url);
  const copie = await cache.match(cle);
  const reseau = fetch(e.request, { cache: 'no-cache' }).then(async rep => {
    if (rep.ok && rep.type === 'basic') {
      await cache.put(cle, rep.clone());
      // nouvelle version en ligne : on prévient la page pour qu'elle propose d'actualiser
      if (copie && e.request.mode === 'navigate' && signature(copie) !== signature(rep)) {
        const clients = await self.clients.matchAll({ type: 'window' });
        clients.forEach(c => c.postMessage({ type: 'nouvelle-version' }));
      }
    }
    return rep;
  });
  if (copie) { e.waitUntil(reseau.catch(() => {})); return copie; }
  return reseau;
}

async function fichierCDN(e, url) {
  const cache = await caches.open(CACHE);
  const copie = await cache.match(e.request);
  // adresse avec un numéro de version précis : le contenu ne change jamais
  const fige = /@\d+\.\d+\.\d+|\/\d+\.\d+\.\d+\//.test(url.pathname) || url.hostname === 'fonts.gstatic.com';
  const reseau = fetch(e.request).then(rep => { if (rep.ok || rep.type === 'opaque') cache.put(e.request, rep.clone()); return rep; });
  if (copie) { if (!fige) e.waitUntil(reseau.catch(() => {})); return copie; }
  return reseau;
}

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin === self.location.origin && url.pathname.startsWith(BASE) && !url.pathname.endsWith('/sw.js')) {
    e.respondWith(pageDuCarnet(e, url));
  } else if (CDN.includes(url.hostname)) {
    e.respondWith(fichierCDN(e, url));
  }
  // tout le reste (Supabase, EmailJS, images externes) passe directement par le réseau
});
