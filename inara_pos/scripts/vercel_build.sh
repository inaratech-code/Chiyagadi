#!/usr/bin/env bash
set -euo pipefail

echo "==> Vercel Flutter build script"

# Install Flutter SDK (stable) if not already present.
# We install into a local folder so Vercel caching (if enabled) can reuse it.
FLUTTER_DIR="${FLUTTER_DIR:-.flutter}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.19.6}"  # Dart 3.3.x, compatible with sdk >=3.0.0 <4.0.0
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

if [[ ! -d "${FLUTTER_DIR}/flutter" ]]; then
  echo "==> Downloading Flutter ${FLUTTER_VERSION}..."
  mkdir -p "${FLUTTER_DIR}"
  curl -L "${FLUTTER_URL}" -o "${FLUTTER_DIR}/${FLUTTER_ARCHIVE}"
  tar -xf "${FLUTTER_DIR}/${FLUTTER_ARCHIVE}" -C "${FLUTTER_DIR}"
  rm -f "${FLUTTER_DIR:?}/${FLUTTER_ARCHIVE}"
else
  echo "==> Flutter already present at ${FLUTTER_DIR}/flutter"
fi

export PATH="$PWD/${FLUTTER_DIR}/flutter/bin:$PATH"
flutter --version

echo "==> Flutter config"
flutter config --enable-web

echo "==> Pub get"
flutter pub get

echo "==> Build web (release)"
flutter build web --release

echo "==> Done. Output is build/web"

