/**
 * ChiyaGadi PWA — caching strategies
 *
 * 1) PRECACHE (install): shell HTML routes + offline fallback.
 * 2) CACHE-FIRST (static): immutable / hashed assets — fastest repeat visits, offline replay.
 * 3) NETWORK-FIRST (navigation): HTML documents — prefer fresh when online.
 * 4) NETWORK-FIRST (runtime): /api/* — always try network, fallback to cache if any.
 * 5) Cross-origin: Firebase/Google APIs — pass-through fetch only (no cache).
 */

var VERSION = "v6";
var CACHE_SHELL = "pos-shell-" + VERSION;
var CACHE_STATIC = "pos-static-" + VERSION;
var CACHE_RUNTIME = "pos-runtime-" + VERSION;

var KNOWN_CACHES = [CACHE_SHELL, CACHE_STATIC, CACHE_RUNTIME];

var PRECACHE_URLS = [
  "/",
  "/login",
  "/menu",
  "/cart",
  "/orders",
  "/offline.html",
];

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches
      .open(CACHE_SHELL)
      .then(function (cache) {
        return Promise.all(
          PRECACHE_URLS.map(function (url) {
            return cache.add(url).catch(function () {});
          })
        );
      })
      .then(function () {
        return self.skipWaiting();
      })
  );
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches
      .keys()
      .then(function (keys) {
        return Promise.all(
          keys.map(function (k) {
            if (KNOWN_CACHES.indexOf(k) === -1) {
              return caches.delete(k);
            }
          })
        );
      })
      .then(function () {
        return self.clients.claim();
      })
  );
});

/** True for hashed Next chunks, images, fonts, manifest, icons — safe for cache-first. */
function isCacheFirstStaticAsset(url) {
  var pathname = url.pathname;
  var search = url.search || "";

  if (pathname.indexOf("/_next/static/") === 0) return true;
  if (pathname.indexOf("/_next/image/") === 0) return true;
  if (pathname.indexOf("/icons/") === 0) return true;

  if (
    /\.(css|js|mjs)(\?|$)/i.test(pathname + search) ||
    /\.(woff2?|ttf|otf|eot)$/i.test(pathname)
  ) {
    return true;
  }
  if (/\.(png|jpe?g|gif|webp|svg|ico|avif)$/i.test(pathname)) return true;

  if (pathname === "/manifest.json" || pathname === "/favicon.ico") return true;
  if (/^\/icon-(\d+)\.png$/i.test(pathname)) return true;

  return false;
}

function isNetworkFirstApi(url) {
  return url.pathname.indexOf("/api/") === 0;
}

function isFirebaseOrAuthRequest(req) {
  var u = req.url;
  return (
    u.indexOf("firebase") !== -1 ||
    u.indexOf("googleapis.com") !== -1 ||
    u.indexOf("identitytoolkit") !== -1 ||
    u.indexOf("securetoken") !== -1
  );
}

function putIfOk(cache, req, res) {
  if (!res || res.status !== 200 || res.type === "opaque") return;
  try {
    return cache.put(req, res.clone());
  } catch (e) {
    return;
  }
}

/**
 * Cache-first: return cached copy immediately; on miss, fetch, store, return.
 * Best for static assets with revision hashes (/_next/static/...).
 */
function cacheFirstStatic(req) {
  return caches.open(CACHE_STATIC).then(function (cache) {
    return cache.match(req).then(function (cached) {
      if (cached) {
        return cached;
      }
      return fetch(req)
        .then(function (res) {
          if (res && res.status === 200) {
            putIfOk(cache, req, res);
          }
          return res;
        })
        .catch(function () {
          return cache.match(req);
        });
    });
  });
}

/**
 * Network-first for HTML: try network; on failure use shell cache or offline page.
 */
function networkFirstNavigation(req) {
  return fetch(req)
    .then(function (res) {
      if (res && res.status === 200) {
        var clone = res.clone();
        caches.open(CACHE_SHELL).then(function (c) {
          putIfOk(c, req, clone);
        });
      }
      return res;
    })
    .catch(function () {
      return caches.match(req).then(function (cached) {
        return cached || caches.match("/offline.html");
      });
    });
}

/**
 * Network-first for API routes; optional stale fallback from runtime cache.
 */
function networkFirstRuntime(req) {
  return fetch(req)
    .then(function (res) {
      var clone = res.clone();
      caches.open(CACHE_RUNTIME).then(function (c) {
        if (res && res.status === 200) putIfOk(c, req, clone);
      });
      return res;
    })
    .catch(function () {
      return caches.match(req).then(function (cached) {
        return (
          cached ||
          new Response(JSON.stringify({ error: "offline" }), {
            status: 503,
            headers: { "Content-Type": "application/json" },
          })
        );
      });
    });
}

self.addEventListener("fetch", function (e) {
  var req = e.request;
  var url = new URL(req.url);

  if (req.method !== "GET") {
    e.respondWith(fetch(req));
    return;
  }

  if (url.origin !== self.location.origin) {
    if (isFirebaseOrAuthRequest(req)) {
      e.respondWith(
        fetch(req).catch(function () {
          return new Response(
            JSON.stringify({ error: "offline" }),
            { status: 503, headers: { "Content-Type": "application/json" } }
          );
        })
      );
    }
    return;
  }

  if (req.mode === "navigate") {
    e.respondWith(networkFirstNavigation(req));
    return;
  }

  if (isNetworkFirstApi(url)) {
    e.respondWith(networkFirstRuntime(req));
    return;
  }

  if (isCacheFirstStaticAsset(url)) {
    e.respondWith(cacheFirstStatic(req));
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
