var CACHE_SHELL = "pos-shell-v1";
var CACHE_STATIC = "pos-static-v1";

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches.open(CACHE_SHELL).then(function (cache) {
      return cache.addAll(["/", "/offline"]);
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (k) { return k !== CACHE_SHELL && k !== CACHE_STATIC; })
          .map(function (k) { return caches.delete(k); })
      );
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function (e) {
  var req = e.request;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then(function (res) {
          var clone = res.clone();
          caches.open(CACHE_SHELL).then(function (c) { c.put(req, clone); });
          return res;
        })
        .catch(function () {
          return caches.match(req).then(function (cached) {
            return cached || caches.match("/offline");
          });
        })
    );
    return;
  }

  if (/\.(js|css|woff2?|ttf|eot)$/i.test(url.pathname)) {
    e.respondWith(
      caches.open(CACHE_STATIC).then(function (cache) {
        return cache.match(req).then(function (cached) {
          return cached || fetch(req).then(function (res) {
            cache.put(req, res.clone());
            return res;
          });
        });
      })
    );
    return;
  }

  e.respondWith(fetch(req));
});

self.addEventListener("online", function () {
  self.clients.matchAll().then(function (clients) {
    clients.forEach(function (c) { c.postMessage({ type: "ONLINE" }); });
  });
});
