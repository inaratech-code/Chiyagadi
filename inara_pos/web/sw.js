var CACHE_NAME = "inara-pos-v1";

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return Promise.allSettled([
        cache.add("/").catch(function () {}),
        cache.add("/index.html").catch(function () {}),
        cache.add("/manifest.json").catch(function () {}),
        cache.add("/flutter.js").catch(function () {}),
      ]);
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (k) { return k !== CACHE_NAME; }).map(function (k) { return caches.delete(k); })
      );
    }).then(function () {
      return self.clients.claim();
    })
  );
});

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then(function (res) {
          var c = res.clone();
          caches.open(CACHE_NAME).then(function (cache) { cache.put(req, c); });
          return res;
        })
        .catch(function () {
          return caches.match(req).then(function (cached) {
            return cached || caches.match("/index.html").then(function (c) {
              return c || caches.match("/");
            });
          });
        })
    );
    return;
  }

  e.respondWith(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.match(req).then(function (cached) {
        return cached || fetch(req).then(function (res) {
          if (res && res.status === 200) cache.put(req, res.clone());
          return res;
        });
      });
    })
  );
});
