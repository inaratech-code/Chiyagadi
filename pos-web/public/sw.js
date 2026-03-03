var CACHE_SHELL = "pos-shell-v3";
var CACHE_STATIC = "pos-static-v3";
var CACHE_RUNTIME = "pos-runtime-v3";

var PRECACHE_URLS = ["/", "/login", "/menu", "/orders", "/offline.html"];

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches.open(CACHE_SHELL).then(function (cache) {
      return Promise.all(
        PRECACHE_URLS.map(function (url) {
          return cache.add(url).catch(function () {});
        })
      );
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys
          .filter(function (k) {
            return k !== CACHE_SHELL && k !== CACHE_STATIC && k !== CACHE_RUNTIME;
          })
          .map(function (k) {
            return caches.delete(k);
          })
      );
    }).then(function () {
      return self.clients.claim();
    })
  );
});

function isCacheFirst(url) {
  var pathname = url.pathname;
  if (pathname.indexOf("/_next/static/") === 0) return true;
  if (pathname.indexOf("/_next/image/") === 0) return true;
  if (pathname.indexOf("/icons/") === 0) return true;
  if (/\.(css|js)(\?|$)/i.test(pathname)) return true;
  return false;
}

function isNetworkFirst(url) {
  var pathname = url.pathname;
  if (pathname.indexOf("/api/") === 0) return true;
  return false;
}

function isFirebaseRequest(req) {
  var u = req.url;
  return (
    u.indexOf("firebase") !== -1 ||
    u.indexOf("googleapis.com") !== -1 ||
    u.indexOf("identitytoolkit") !== -1 ||
    u.indexOf("securetoken") !== -1
  );
}

self.addEventListener("fetch", function (e) {
  var req = e.request;
  var url = new URL(req.url);

  if (req.method !== "GET") {
    e.respondWith(fetch(req));
    return;
  }

  if (url.origin !== self.location.origin) {
    if (isFirebaseRequest(req)) {
      e.respondWith(
        fetch(req).catch(function () {
          return new Response(
            JSON.stringify({ error: "offline" }),
            { status: 503, headers: { "Content-Type": "application/json" } }
          );
        }
      );
    }
    return;
  }

  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then(function (res) {
          var clone = res.clone();
          caches.open(CACHE_SHELL).then(function (c) {
            c.put(req, clone);
          });
          return res;
        })
        .catch(function () {
          return caches.match(req).then(function (cached) {
            return cached || caches.match("/offline.html");
          });
        })
    );
    return;
  }

  if (isCacheFirst(url)) {
    e.respondWith(
      caches.open(CACHE_STATIC).then(function (cache) {
        return cache.match(req).then(function (cached) {
          return (
            cached ||
            fetch(req).then(function (res) {
              if (res && res.status === 200) {
                cache.put(req, res.clone());
              }
              return res;
            })
          );
        });
      })
    );
    return;
  }

  if (isNetworkFirst(url)) {
    e.respondWith(
      fetch(req)
        .then(function (res) {
          var clone = res.clone();
          caches.open(CACHE_RUNTIME).then(function (c) {
            c.put(req, clone);
          });
          return res;
        })
        .catch(function () {
          return caches.match(req).then(function (cached) {
            return (
              cached ||
              new Response(
                JSON.stringify({ error: "offline" }),
                { status: 503, headers: { "Content-Type": "application/json" } }
              )
            );
          });
        })
    );
    return;
  }

  e.respondWith(fetch(req));
});

self.addEventListener("online", function () {
  self.clients.matchAll().then(function (clients) {
    clients.forEach(function (c) {
      c.postMessage({ type: "ONLINE" });
    });
  });
});
